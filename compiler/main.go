package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/types"
	"log"
	"os"
	"strings"

	"golang.org/x/tools/go/packages"
	"golang.org/x/tools/go/ssa"
	"golang.org/x/tools/go/ssa/ssautil"
)

type HybridIR struct {
	Packages []PackageIR `json:"packages"`
	MainPkg  string      `json:"main_package"`
}

type PackageIR struct {
	Path       string       `json:"path"`
	Name       string       `json:"name"`
	Types      []TypeDef    `json:"types"`
	Functions  []FunctionIR `json:"functions"`
	Globals    []GlobalVar  `json:"globals"`
	Constants  []ConstDef   `json:"constants"`
	Imports    []string     `json:"imports"`
	CGOImports []CGOImport  `json:"cgo_imports"`
}

type CGOImport struct {
	CFlags  []string `json:"cflags"`
	LDFlags []string `json:"ldflags"`
	Headers []string `json:"headers"`
	PkgPath string   `json:"pkg_path"`
}

type TypeDef struct {
	Name       string         `json:"name"`
	Kind       string         `json:"kind"`
	Fields     []FieldDef     `json:"fields,omitempty"`
	Methods    []string       `json:"methods,omitempty"`
	Underlying string         `json:"underlying,omitempty"`
	Signature  *FuncSignature `json:"signature,omitempty"`
}

type FieldDef struct {
	Name string `json:"name"`
	Type string `json:"typ"`
	Tag  string `json:"tag,omitempty"`
}

type FunctionIR struct {
	Name      string         `json:"name"`
	Receiver  *ReceiverInfo  `json:"receiver,omitempty"`
	Signature FuncSignature  `json:"signature"`
	Body      *BodyIR        `json:"body,omitempty"`
	IsMethod  bool           `json:"is_method"`
	Package   string         `json:"package"`
}

type ReceiverInfo struct {
	Name    string `json:"name"`
	Type    string `json:"type"`
	Pointer bool   `json:"pointer"`
}

type FuncSignature struct {
	Params   []Param `json:"params"`
	Results  []Param `json:"results"`
	Variadic bool    `json:"variadic"`
}

type Param struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type BodyIR struct {
	Blocks      []BlockIR         `json:"blocks"`
	Locals      []LocalVar        `json:"locals"`
	FreeVars    []string          `json:"free_vars"`
	StructHints map[string]HintIR `json:"struct_hints"`
	Defers      []DeferInfo       `json:"defers"`
}

type HintIR struct {
	Kind   string   `json:"kind"`
	Lines  []int    `json:"lines"`
	Labels []string `json:"labels,omitempty"`
}

type DeferInfo struct {
	BlockID int    `json:"block_id"`
	Call    string `json:"call"`
}

type BlockIR struct {
	ID           int           `json:"id"`
	Instructions []Instruction `json:"instructions"`
	Successors   []int         `json:"successors"`
	Comment      string        `json:"comment,omitempty"`
}

type Instruction struct {
	Op       string   `json:"op"`
	Args     []string `json:"args,omitempty"`
	Type     string   `json:"type,omitempty"`
	Result   string   `json:"result,omitempty"`
	Comment  string   `json:"comment,omitempty"`
	Position int      `json:"position,omitempty"`
}

type LocalVar struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type GlobalVar struct {
	Name  string `json:"name"`
	Type  string `json:"type"`
	Value string `json:"value,omitempty"`
}

type ConstDef struct {
	Name  string `json:"name"`
	Type  string `json:"type"`
	Value string `json:"value"`
}

var (
	inputPath  = flag.String("input", ".", "Input Go package path")
	outputPath = flag.String("output", "output.json", "Output JSON file")
	verbose    = flag.Bool("v", false, "Verbose output")
)

func main() {
	flag.Parse()

	cfg := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
			packages.NeedImports | packages.NeedDeps | packages.NeedTypes |
			packages.NeedSyntax | packages.NeedTypesInfo,
	}

	initial, err := packages.Load(cfg, *inputPath)
	if err != nil {
		log.Fatalf("Failed to load packages: %v", err)
	}

	if packages.PrintErrors(initial) > 0 {
		log.Fatal("Package loading errors occurred")
	}

	prog, pkgs := ssautil.AllPackages(initial, ssa.SanityCheckFunctions|ssa.BuildSerially)
	prog.Build()

	ir := HybridIR{
		Packages: make([]PackageIR, 0),
	}

	processedPkgs := make(map[string]bool)

	for _, pkg := range pkgs {
		if pkg == nil || processedPkgs[pkg.Pkg.Path()] {
			continue
		}
		processedPkgs[pkg.Pkg.Path()] = true

		if *verbose {
			log.Printf("Processing package: %s", pkg.Pkg.Path())
		}

		pkgIR := processPackage(pkg, initial)
		ir.Packages = append(ir.Packages, pkgIR)

		if pkg.Func("main") != nil {
			ir.MainPkg = pkg.Pkg.Path()
		}
	}

	data, err := json.MarshalIndent(ir, "", "  ")
	if err != nil {
		log.Fatalf("Failed to marshal IR: %v", err)
	}

	if err := os.WriteFile(*outputPath, data, 0644); err != nil {
		log.Fatalf("Failed to write output: %v", err)
	}

	log.Printf("Successfully generated IR: %s", *outputPath)
}

func processPackage(pkg *ssa.Package, initial []*packages.Package) PackageIR {
	var goPackage *packages.Package
	for _, p := range initial {
		if p.PkgPath == pkg.Pkg.Path() {
			goPackage = p
			break
		}
	}

	pkgIR := PackageIR{
		Path:      pkg.Pkg.Path(),
		Name:      pkg.Pkg.Name(),
		Types:     extractTypes(pkg),
		Functions: make([]FunctionIR, 0),
		Globals:   extractGlobals(pkg),
		Constants: extractConstants(pkg),
		Imports:   extractImports(pkg),
	}

	if goPackage != nil {
		pkgIR.CGOImports = extractCGOImports(goPackage)
	}

	for _, mem := range pkg.Members {
		switch m := mem.(type) {
		case *ssa.Function:
			if m.Blocks != nil {
				fnIR := processFunction(m, goPackage)
				pkgIR.Functions = append(pkgIR.Functions, fnIR)
			}
		}
	}

	return pkgIR
}

func extractCGOImports(pkg *packages.Package) []CGOImport {
	cgoImports := make([]CGOImport, 0)

	for _, file := range pkg.Syntax {
		for _, cg := range file.Comments {
			for _, comment := range cg.List {
				text := comment.Text
				if strings.HasPrefix(text, "// #cgo") || strings.HasPrefix(text, "//#cgo") {
					cgoImport := parseCGODirective(text, pkg.PkgPath)
					if cgoImport != nil {
						cgoImports = append(cgoImports, *cgoImport)
					}
				}
			}
		}
	}

	return cgoImports
}

func parseCGODirective(directive string, pkgPath string) *CGOImport {
	directive = strings.TrimPrefix(directive, "//")
	directive = strings.TrimPrefix(directive, "// ")
	directive = strings.TrimSpace(directive)

	if !strings.HasPrefix(directive, "#cgo") {
		return nil
	}

	cgo := &CGOImport{
		PkgPath: pkgPath,
		CFlags:  make([]string, 0),
		LDFlags: make([]string, 0),
		Headers: make([]string, 0),
	}

	parts := strings.Fields(directive)
	if len(parts) < 3 {
		return nil
	}

	flagType := parts[1]
	flags := strings.Join(parts[2:], " ")

	switch flagType {
	case "CFLAGS:":
		cgo.CFlags = append(cgo.CFlags, flags)
	case "LDFLAGS:":
		cgo.LDFlags = append(cgo.LDFlags, flags)
	}

	return cgo
}

func extractTypes(pkg *ssa.Package) []TypeDef {
	typeDefs := make([]TypeDef, 0)
	seen := make(map[string]bool)

	scope := pkg.Pkg.Scope()
	for _, name := range scope.Names() {
		obj := scope.Lookup(name)
		tn, ok := obj.(*types.TypeName)
		if !ok {
			continue
		}

		if seen[tn.Name()] {
			continue
		}
		seen[tn.Name()] = true

		typeDef := TypeDef{
			Name:    tn.Name(),
			Methods: make([]string, 0),
		}

		underlying := tn.Type().Underlying()

		switch t := underlying.(type) {
		case *types.Struct:
			typeDef.Kind = "struct"
			typeDef.Fields = extractStructFields(t)
		case *types.Interface:
			typeDef.Kind = "interface"
			typeDef.Fields = extractInterfaceMethods(t)
		case *types.Signature:
			typeDef.Kind = "func"
			sig := extractSignature(t)
			typeDef.Signature = &sig
		default:
			typeDef.Kind = "alias"
			typeDef.Underlying = types.TypeString(underlying, nil)
		}

		mset := types.NewMethodSet(types.NewPointer(tn.Type()))
		for i := 0; i < mset.Len(); i++ {
			m := mset.At(i)
			typeDef.Methods = append(typeDef.Methods, m.Obj().Name())
		}

		typeDefs = append(typeDefs, typeDef)
	}

	return typeDefs
}

func extractStructFields(s *types.Struct) []FieldDef {
	fields := make([]FieldDef, 0)
	for i := 0; i < s.NumFields(); i++ {
		f := s.Field(i)
		field := FieldDef{
			Name: f.Name(),
			Type: types.TypeString(f.Type(), nil),
		}
		if s.Tag(i) != "" {
			field.Tag = s.Tag(i)
		}
		fields = append(fields, field)
	}
	return fields
}

func extractInterfaceMethods(iface *types.Interface) []FieldDef {
	methods := make([]FieldDef, 0)
	for i := 0; i < iface.NumMethods(); i++ {
		m := iface.Method(i)
		method := FieldDef{
			Name: m.Name(),
			Type: types.TypeString(m.Type(), nil),
		}
		methods = append(methods, method)
	}
	return methods
}

func extractSignature(sig *types.Signature) FuncSignature {
	fs := FuncSignature{
		Params:   make([]Param, 0),
		Results:  make([]Param, 0),
		Variadic: sig.Variadic(),
	}

	params := sig.Params()
	for i := 0; i < params.Len(); i++ {
		p := params.At(i)
		fs.Params = append(fs.Params, Param{
			Name: p.Name(),
			Type: types.TypeString(p.Type(), nil),
		})
	}

	results := sig.Results()
	for i := 0; i < results.Len(); i++ {
		r := results.At(i)
		fs.Results = append(fs.Results, Param{
			Name: r.Name(),
			Type: types.TypeString(r.Type(), nil),
		})
	}

	return fs
}

func extractGlobals(pkg *ssa.Package) []GlobalVar {
	globals := make([]GlobalVar, 0)
	for _, mem := range pkg.Members {
		if g, ok := mem.(*ssa.Global); ok {
			global := GlobalVar{
				Name: g.Name(),
				Type: types.TypeString(g.Type(), nil),
			}
			globals = append(globals, global)
		}
	}
	return globals
}

func extractConstants(pkg *ssa.Package) []ConstDef {
	constants := make([]ConstDef, 0)
	scope := pkg.Pkg.Scope()
	for _, name := range scope.Names() {
		obj := scope.Lookup(name)
		if c, ok := obj.(*types.Const); ok {
			constant := ConstDef{
				Name:  c.Name(),
				Type:  types.TypeString(c.Type(), nil),
				Value: c.Val().String(),
			}
			constants = append(constants, constant)
		}
	}
	return constants
}

func extractImports(pkg *ssa.Package) []string {
	imports := make([]string, 0)
	for _, imp := range pkg.Pkg.Imports() {
		imports = append(imports, imp.Path())
	}
	return imports
}

func processFunction(fn *ssa.Function, goPackage *packages.Package) FunctionIR {
	fnIR := FunctionIR{
		Name:     fn.Name(),
		Package:  fn.Pkg.Pkg.Path(),
		IsMethod: fn.Signature.Recv() != nil,
	}

	if fn.Signature.Recv() != nil {
		recv := fn.Signature.Recv()
		recvType := recv.Type()
		pointer := false
		if ptr, ok := recvType.(*types.Pointer); ok {
			recvType = ptr.Elem()
			pointer = true
		}
		fnIR.Receiver = &ReceiverInfo{
			Name:    recv.Name(),
			Type:    types.TypeString(recvType, nil),
			Pointer: pointer,
		}
	}

	fnIR.Signature = extractSignature(fn.Signature)

	if fn.Blocks != nil {
		body := &BodyIR{
			Blocks:      make([]BlockIR, 0),
			Locals:      extractLocals(fn),
			FreeVars:    extractFreeVars(fn),
			StructHints: extractASTHints(fn, goPackage),
			Defers:      make([]DeferInfo, 0),
		}

		for i, block := range fn.Blocks {
			blockIR := BlockIR{
				ID:           i,
				Instructions: make([]Instruction, 0),
				Successors:   make([]int, 0),
			}

			for _, instr := range block.Instrs {
				inst := convertInstruction(instr)
				blockIR.Instructions = append(blockIR.Instructions, inst)

				if _, ok := instr.(*ssa.Defer); ok {
					body.Defers = append(body.Defers, DeferInfo{
						BlockID: i,
						Call:    inst.Comment,
					})
				}
			}

			for _, succ := range block.Succs {
				for j, b := range fn.Blocks {
					if b == succ {
						blockIR.Successors = append(blockIR.Successors, j)
						break
					}
				}
			}

			body.Blocks = append(body.Blocks, blockIR)
		}

		fnIR.Body = body
	}

	return fnIR
}

func extractLocals(fn *ssa.Function) []LocalVar {
	locals := make([]LocalVar, 0)
	seen := make(map[string]bool)

	for _, block := range fn.Blocks {
		for _, instr := range block.Instrs {
			if alloc, ok := instr.(*ssa.Alloc); ok {
				if alloc.Comment != "" && !seen[alloc.Name()] {
					locals = append(locals, LocalVar{
						Name: alloc.Name(),
						Type: types.TypeString(alloc.Type(), nil),
					})
					seen[alloc.Name()] = true
				}
			}
		}
	}

	return locals
}

func extractFreeVars(fn *ssa.Function) []string {
	freeVars := make([]string, 0)
	for _, fv := range fn.FreeVars {
		freeVars = append(freeVars, fv.Name())
	}
	return freeVars
}

func extractASTHints(fn *ssa.Function, goPackage *packages.Package) map[string]HintIR {
	hints := make(map[string]HintIR)

	if goPackage == nil || fn.Syntax() == nil {
		return hints
	}

	ast.Inspect(fn.Syntax(), func(n ast.Node) bool {
		switch stmt := n.(type) {
		case *ast.IfStmt:
			hints[fmt.Sprintf("if_%d", stmt.Pos())] = HintIR{
				Kind:  "if",
				Lines: []int{int(stmt.Pos())},
			}
		case *ast.ForStmt:
			hints[fmt.Sprintf("for_%d", stmt.Pos())] = HintIR{
				Kind:  "for",
				Lines: []int{int(stmt.Pos())},
			}
		case *ast.RangeStmt:
			hints[fmt.Sprintf("range_%d", stmt.Pos())] = HintIR{
				Kind:  "for",
				Lines: []int{int(stmt.Pos())},
			}
		case *ast.SwitchStmt:
			hints[fmt.Sprintf("switch_%d", stmt.Pos())] = HintIR{
				Kind:  "switch",
				Lines: []int{int(stmt.Pos())},
			}
		case *ast.SelectStmt:
			hints[fmt.Sprintf("select_%d", stmt.Pos())] = HintIR{
				Kind:  "select",
				Lines: []int{int(stmt.Pos())},
			}
		case *ast.DeferStmt:
			hints[fmt.Sprintf("defer_%d", stmt.Pos())] = HintIR{
				Kind:  "defer",
				Lines: []int{int(stmt.Pos())},
			}
		}
		return true
	})

	return hints
}

func convertInstruction(instr ssa.Instruction) Instruction {
	inst := Instruction{
		Op:      fmt.Sprintf("%T", instr),
		Args:    make([]string, 0),
		Comment: instr.String(),
	}

	inst.Op = strings.TrimPrefix(inst.Op, "*ssa.")

	if v, ok := instr.(ssa.Value); ok {
		inst.Result = v.Name()
		inst.Type = types.TypeString(v.Type(), nil)
	}

	for _, op := range instr.Operands(nil) {
		if op != nil && *op != nil {
			inst.Args = append(inst.Args, (*op).Name())
		}
	}

	return inst
}

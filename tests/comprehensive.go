package main

import (
	"fmt"
	"sync"
	"time"
)

// ============================================
// COMPREHENSIVE GONIM TEST SUITE
// Tests all major Go features and stdlib
// ============================================

// Custom types
type (
	Counter struct {
		mu    sync.Mutex
		value int
	}

	Result struct {
		ID    int
		Value string
		Time  time.Time
	}

	Worker interface {
		Process(data string) Result
		GetID() int
	}

	SimpleWorker struct {
		id int
	}
)

// Implement interface
func (w *SimpleWorker) Process(data string) Result {
	return Result{
		ID:    w.id,
		Value: data,
		Time:  time.Now(),
	}
}

func (w *SimpleWorker) GetID() int {
	return w.id
}

// Counter methods
func (c *Counter) Increment() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.value++
}

func (c *Counter) Get() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.value
}

func main() {
	fmt.Println("╔════════════════════════════════════════╗")
	fmt.Println("║  GONIM COMPREHENSIVE TEST SUITE       ║")
	fmt.Println("╚════════════════════════════════════════╝")

	// Run all tests
	testBasicTypes()
	testSlicesAndMaps()
	testGoroutinesAndChannels()
	testSync()
	testDefer()
	testInterfaces()
	testTimeOperations()
	testErrorHandling()
	testComplexWorkflow()

	fmt.Println("\n✓ All tests completed successfully!")
}

// Test 1: Basic types and operations
func testBasicTypes() {
	fmt.Println("\n[1] Testing Basic Types...")

	// Integers
	var i int = 42
	var i8 int8 = -128
	var u uint = 100
	fmt.Printf("  int: %d, int8: %d, uint: %d\n", i, i8, u)

	// Floats
	var f32 float32 = 3.14
	var f64 float64 = 2.71828
	fmt.Printf("  float32: %.2f, float64: %.5f\n", f32, f64)

	// Strings
	s := "Hello, GONIM!"
	fmt.Printf("  string: %s (len=%d)\n", s, len(s))

	// Booleans
	b := true
	fmt.Printf("  bool: %t\n", b)
}

// Test 2: Slices and Maps
func testSlicesAndMaps() {
	fmt.Println("\n[2] Testing Slices and Maps...")

	// Slices
	slice := []int{1, 2, 3, 4, 5}
	slice = append(slice, 6, 7, 8)
	fmt.Printf("  Slice: %v (len=%d, cap=%d)\n", slice, len(slice), cap(slice))

	// Slice operations
	subSlice := slice[2:5]
	fmt.Printf("  Sub-slice [2:5]: %v\n", subSlice)

	// Maps
	m := make(map[string]int)
	m["one"] = 1
	m["two"] = 2
	m["three"] = 3

	fmt.Printf("  Map: ")
	for k, v := range m {
		fmt.Printf("%s=%d ", k, v)
	}
	fmt.Println()

	// Map lookup
	if val, ok := m["two"]; ok {
		fmt.Printf("  Found 'two': %d\n", val)
	}

	delete(m, "two")
	fmt.Printf("  After delete: %v\n", m)
}

// Test 3: Goroutines and Channels
func testGoroutinesAndChannels() {
	fmt.Println("\n[3] Testing Goroutines and Channels...")

	// Unbuffered channel
	ch := make(chan int)

	go func() {
		for i := 1; i <= 5; i++ {
			ch <- i * i
		}
		close(ch)
	}()

	fmt.Print("  Received: ")
	for val := range ch {
		fmt.Printf("%d ", val)
	}
	fmt.Println()

	// Buffered channel
	buffered := make(chan string, 3)
	buffered <- "alpha"
	buffered <- "beta"
	buffered <- "gamma"
	close(buffered)

	fmt.Print("  Buffered: ")
	for msg := range buffered {
		fmt.Printf("%s ", msg)
	}
	fmt.Println()

	// Multiple goroutines
	results := make(chan int, 10)
	for i := 0; i < 10; i++ {
		go func(n int) {
			results <- n * 2
		}(i)
	}

	// Collect results
	collected := make([]int, 10)
	for i := 0; i < 10; i++ {
		collected[i] = <-results
	}
	fmt.Printf("  Parallel results: %v\n", collected)
}

// Test 4: Sync primitives
func testSync() {
	fmt.Println("\n[4] Testing Sync Primitives...")

	// WaitGroup
	var wg sync.WaitGroup
	counter := &Counter{}

	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			counter.Increment()
		}()
	}

	wg.Wait()
	fmt.Printf("  Counter (100 goroutines): %d\n", counter.Get())

	// Once
	var once sync.Once
	executed := 0
	for i := 0; i < 10; i++ {
		once.Do(func() {
			executed++
		})
	}
	fmt.Printf("  Once executed: %d times (should be 1)\n", executed)

	// Mutex
	var mu sync.Mutex
	shared := 0
	for i := 0; i < 1000; i++ {
		go func() {
			mu.Lock()
			shared++
			mu.Unlock()
		}()
	}
	time.Sleep(100 * time.Millisecond)
	mu.Lock()
	fmt.Printf("  Mutex protected counter: %d\n", shared)
	mu.Unlock()
}

// Test 5: Defer statement
func testDefer() {
	fmt.Println("\n[5] Testing Defer...")

	fmt.Print("  Defer order: ")
	defer fmt.Print("3 ")
	defer fmt.Print("2 ")
	defer fmt.Print("1 ")
	fmt.Print("Start ")

	// Defer in function
	func() {
		defer fmt.Print("(inner defer) ")
		fmt.Print("Inside ")
	}()

	fmt.Println()
}

// Test 6: Interfaces
func testInterfaces() {
	fmt.Println("\n[6] Testing Interfaces...")

	workers := []Worker{
		&SimpleWorker{id: 1},
		&SimpleWorker{id: 2},
		&SimpleWorker{id: 3},
	}

	for _, w := range workers {
		result := w.Process(fmt.Sprintf("task-%d", w.GetID()))
		fmt.Printf("  Worker %d: %s at %v\n",
			result.ID, result.Value, result.Time.Format("15:04:05"))
	}
}

// Test 7: Time operations
func testTimeOperations() {
	fmt.Println("\n[7] Testing Time Operations...")

	now := time.Now()
	fmt.Printf("  Current time: %s\n", now.Format("2006-01-02 15:04:05"))

	// Duration
	duration := 2 * time.Second
	fmt.Printf("  Duration: %v\n", duration)

	// Timer
	timer := time.NewTimer(10 * time.Millisecond)
	<-timer.C
	fmt.Println("  Timer fired!")

	// Ticker
	ticker := time.NewTicker(5 * time.Millisecond)
	count := 0
	for range ticker.C {
		count++
		if count >= 3 {
			ticker.Stop()
			break
		}
	}
	fmt.Printf("  Ticker ticked %d times\n", count)
}

// Test 8: Error handling
func testErrorHandling() {
	fmt.Println("\n[8] Testing Error Handling...")

	// Function that returns error
	divide := func(a, b int) (int, error) {
		if b == 0 {
			return 0, fmt.Errorf("division by zero")
		}
		return a / b, nil
	}

	if result, err := divide(10, 2); err != nil {
		fmt.Printf("  Error: %v\n", err)
	} else {
		fmt.Printf("  10 / 2 = %d\n", result)
	}

	if _, err := divide(10, 0); err != nil {
		fmt.Printf("  Expected error: %v\n", err)
	}
}

// Test 9: Complex workflow
func testComplexWorkflow() {
	fmt.Println("\n[9] Testing Complex Workflow...")

	// Pipeline pattern
	gen := func(nums ...int) <-chan int {
		out := make(chan int)
		go func() {
			for _, n := range nums {
				out <- n
			}
			close(out)
		}()
		return out
	}

	sq := func(in <-chan int) <-chan int {
		out := make(chan int)
		go func() {
			for n := range in {
				out <- n * n
			}
			close(out)
		}()
		return out
	}

	// Build pipeline
	c := gen(1, 2, 3, 4, 5)
	out := sq(sq(c)) // Square twice

	fmt.Print("  Pipeline (n^4): ")
	for val := range out {
		fmt.Printf("%d ", val)
	}
	fmt.Println()

	// Fan-out, fan-in pattern
	fanOut := func(in <-chan int, n int) []<-chan int {
		channels := make([]<-chan int, n)
		for i := 0; i < n; i++ {
			channels[i] = sq(in)
		}
		return channels
	}

	merge := func(cs ...<-chan int) <-chan int {
		var wg sync.WaitGroup
		out := make(chan int)

		output := func(c <-chan int) {
			for n := range c {
				out <- n
			}
			wg.Done()
		}

		wg.Add(len(cs))
		for _, c := range cs {
			go output(c)
		}

		go func() {
			wg.Wait()
			close(out)
		}()

		return out
	}

	input := gen(1, 2, 3, 4)
	workers := fanOut(input, 3)
	result := merge(workers...)

	sum := 0
	for val := range result {
		sum += val
	}
	fmt.Printf("  Fan-out/Fan-in sum: %d\n", sum)
}

// Bonus: Demonstrate select statement
func demonstrateSelect() {
	ch1 := make(chan string)
	ch2 := make(chan string)

	go func() {
		time.Sleep(100 * time.Millisecond)
		ch1 <- "channel 1"
	}()

	go func() {
		time.Sleep(200 * time.Millisecond)
		ch2 <- "channel 2"
	}()

	for i := 0; i < 2; i++ {
		select {
		case msg1 := <-ch1:
			fmt.Println("Received:", msg1)
		case msg2 := <-ch2:
			fmt.Println("Received:", msg2)
		}
	}
}

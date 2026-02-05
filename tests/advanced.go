package main

import (
	"fmt"
	"sync"
	"time"
)

// =====================================================
// Advanced Go Features Demonstration
// Generics, Advanced Concurrency, Reflection patterns
// =====================================================

// Generic types
type Stack[T any] struct {
	items []T
	mu    sync.RWMutex
}

func NewStack[T any]() *Stack[T] {
	return &Stack[T]{
		items: make([]T, 0),
	}
}

func (s *Stack[T]) Push(item T) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items = append(s.items, item)
}

func (s *Stack[T]) Pop() (T, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.items) == 0 {
		var zero T
		return zero, false
	}

	item := s.items[len(s.items)-1]
	s.items = s.items[:len(s.items)-1]
	return item, true
}

func (s *Stack[T]) Len() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.items)
}

// Generic map/filter/reduce
func Map[T, U any](slice []T, fn func(T) U) []U {
	result := make([]U, len(slice))
	for i, v := range slice {
		result[i] = fn(v)
	}
	return result
}

func Filter[T any](slice []T, fn func(T) bool) []T {
	result := make([]T, 0)
	for _, v := range slice {
		if fn(v) {
			result = append(result, v)
		}
	}
	return result
}

func Reduce[T, U any](slice []T, initial U, fn func(U, T) U) U {
	acc := initial
	for _, v := range slice {
		acc = fn(acc, v)
	}
	return acc
}

// Worker pool pattern
type Job struct {
	ID   int
	Data string
}

type JobResult struct {
	Job    Job
	Result string
	Error  error
}

type WorkerPool struct {
	workers   int
	jobs      chan Job
	results   chan JobResult
	wg        sync.WaitGroup
	closeOnce sync.Once
}

func NewWorkerPool(workers int) *WorkerPool {
	return &WorkerPool{
		workers: workers,
		jobs:    make(chan Job, 100),
		results: make(chan JobResult, 100),
	}
}

func (wp *WorkerPool) Start() {
	for i := 0; i < wp.workers; i++ {
		wp.wg.Add(1)
		go wp.worker(i)
	}
}

func (wp *WorkerPool) worker(id int) {
	defer wp.wg.Done()

	for job := range wp.jobs {
		// Simulate work
		time.Sleep(10 * time.Millisecond)

		result := JobResult{
			Job:    job,
			Result: fmt.Sprintf("Worker %d processed: %s", id, job.Data),
			Error:  nil,
		}

		wp.results <- result
	}
}

func (wp *WorkerPool) Submit(job Job) {
	wp.jobs <- job
}

func (wp *WorkerPool) Results() <-chan JobResult {
	return wp.results
}

func (wp *WorkerPool) Close() {
	wp.closeOnce.Do(func() {
		close(wp.jobs)
		wp.wg.Wait()
		close(wp.results)
	})
}

// Context pattern simulation
type Context struct {
	Done   <-chan struct{}
	values map[string]interface{}
	mu     sync.RWMutex
}

func Background() *Context {
	return &Context{
		Done:   make(<-chan struct{}),
		values: make(map[string]interface{}),
	}
}

func WithTimeout(parent *Context, timeout time.Duration) (*Context, func()) {
	done := make(chan struct{})
	ctx := &Context{
		Done:   done,
		values: make(map[string]interface{}),
	}

	// Copy parent values
	parent.mu.RLock()
	for k, v := range parent.values {
		ctx.values[k] = v
	}
	parent.mu.RUnlock()

	timer := time.AfterFunc(timeout, func() {
		close(done)
	})

	cancel := func() {
		timer.Stop()
		close(done)
	}

	return ctx, cancel
}

func (c *Context) Value(key string) interface{} {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.values[key]
}

func (c *Context) WithValue(key string, value interface{}) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.values[key] = value
}

// Advanced channel patterns
type Publisher[T any] struct {
	subscribers []chan T
	mu          sync.RWMutex
}

func NewPublisher[T any]() *Publisher[T] {
	return &Publisher[T]{
		subscribers: make([]chan T, 0),
	}
}

func (p *Publisher[T]) Subscribe() <-chan T {
	p.mu.Lock()
	defer p.mu.Unlock()

	ch := make(chan T, 10)
	p.subscribers = append(p.subscribers, ch)
	return ch
}

func (p *Publisher[T]) Publish(item T) {
	p.mu.RLock()
	defer p.mu.RUnlock()

	for _, ch := range p.subscribers {
		select {
		case ch <- item:
		default:
			// Skip if channel is full
		}
	}
}

func (p *Publisher[T]) Close() {
	p.mu.Lock()
	defer p.mu.Unlock()

	for _, ch := range p.subscribers {
		close(ch)
	}
	p.subscribers = nil
}

func main() {
	fmt.Println("=== Advanced Go Features ===\n")

	// Test 1: Generics
	testGenerics()

	// Test 2: Worker Pool
	testWorkerPool()

	// Test 3: Pub/Sub
	testPubSub()

	// Test 4: Context
	testContext()

	fmt.Println("\n✓ All advanced tests completed!")
}

func testGenerics() {
	fmt.Println("[1] Testing Generics...")

	// Stack with integers
	intStack := NewStack[int]()
	intStack.Push(1)
	intStack.Push(2)
	intStack.Push(3)

	fmt.Print("  Int stack: ")
	for intStack.Len() > 0 {
		if val, ok := intStack.Pop(); ok {
			fmt.Printf("%d ", val)
		}
	}
	fmt.Println()

	// Stack with strings
	strStack := NewStack[string]()
	strStack.Push("hello")
	strStack.Push("world")

	fmt.Print("  String stack: ")
	for strStack.Len() > 0 {
		if val, ok := strStack.Pop(); ok {
			fmt.Printf("%s ", val)
		}
	}
	fmt.Println()

	// Map/Filter/Reduce
	numbers := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

	squared := Map(numbers, func(n int) int { return n * n })
	fmt.Printf("  Squared: %v\n", squared)

	evens := Filter(numbers, func(n int) bool { return n%2 == 0 })
	fmt.Printf("  Evens: %v\n", evens)

	sum := Reduce(numbers, 0, func(acc, n int) int { return acc + n })
	fmt.Printf("  Sum: %d\n", sum)
}

func testWorkerPool() {
	fmt.Println("\n[2] Testing Worker Pool...")

	pool := NewWorkerPool(5)
	pool.Start()

	// Submit jobs
	go func() {
		for i := 0; i < 20; i++ {
			pool.Submit(Job{
				ID:   i,
				Data: fmt.Sprintf("task-%d", i),
			})
		}
		pool.Close()
	}()

	// Collect results
	completed := 0
	for result := range pool.Results() {
		completed++
		if completed <= 3 {
			fmt.Printf("  %s\n", result.Result)
		}
	}
	fmt.Printf("  Completed %d jobs\n", completed)
}

func testPubSub() {
	fmt.Println("\n[3] Testing Pub/Sub...")

	pub := NewPublisher[string]()

	// Create subscribers
	sub1 := pub.Subscribe()
	sub2 := pub.Subscribe()
	sub3 := pub.Subscribe()

	var wg sync.WaitGroup

	// Subscriber 1
	wg.Add(1)
	go func() {
		defer wg.Done()
		for msg := range sub1 {
			fmt.Printf("  Sub1 received: %s\n", msg)
		}
	}()

	// Subscriber 2
	wg.Add(1)
	go func() {
		defer wg.Done()
		count := 0
		for range sub2 {
			count++
		}
		fmt.Printf("  Sub2 received %d messages\n", count)
	}()

	// Subscriber 3
	wg.Add(1)
	go func() {
		defer wg.Done()
		count := 0
		for range sub3 {
			count++
		}
		fmt.Printf("  Sub3 received %d messages\n", count)
	}()

	// Publish messages
	messages := []string{"alpha", "beta", "gamma", "delta"}
	for _, msg := range messages {
		pub.Publish(msg)
		time.Sleep(10 * time.Millisecond)
	}

	pub.Close()
	wg.Wait()
}

func testContext() {
	fmt.Println("\n[4] Testing Context...")

	ctx := Background()
	ctx.WithValue("user", "alice")
	ctx.WithValue("request_id", "req-12345")

	fmt.Printf("  User: %v\n", ctx.Value("user"))
	fmt.Printf("  Request ID: %v\n", ctx.Value("request_id"))

	// With timeout
	timeoutCtx, cancel := WithTimeout(ctx, 50*time.Millisecond)
	defer cancel()

	select {
	case <-timeoutCtx.Done:
		fmt.Println("  Context timed out (as expected)")
	case <-time.After(100 * time.Millisecond):
		fmt.Println("  Context should have timed out")
	}
}

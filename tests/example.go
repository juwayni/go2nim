package main

import (
	"fmt"
	"sync"
	"time"
)

// Demonstrate basic Go features
func main() {
	fmt.Println("=== GONIM Test Suite ===")
	
	// Test 1: Basic printing
	testBasicPrint()
	
	// Test 2: Goroutines and channels
	testGoroutines()
	
	// Test 3: WaitGroups
	testWaitGroup()
	
	// Test 4: Defer
	testDefer()
	
	// Test 5: Structs and methods
	testStructs()
	
	fmt.Println("\n=== All Tests Passed ===")
}

func testBasicPrint() {
	fmt.Println("\n--- Test 1: Basic Print ---")
	fmt.Printf("Hello from GONIM! Pi = %.2f\n", 3.14159)
	
	name := "Gopher"
	age := 10
	fmt.Printf("Name: %s, Age: %d\n", name, age)
}

func testGoroutines() {
	fmt.Println("\n--- Test 2: Goroutines and Channels ---")
	
	ch := make(chan string, 3)
	
	// Start goroutines
	go func() {
		time.Sleep(100 * time.Millisecond)
		ch <- "Hello"
	}()
	
	go func() {
		time.Sleep(200 * time.Millisecond)
		ch <- "from"
	}()
	
	go func() {
		time.Sleep(300 * time.Millisecond)
		ch <- "goroutines!"
	}()
	
	// Receive from channel
	for i := 0; i < 3; i++ {
		msg := <-ch
		fmt.Println("Received:", msg)
	}
}

func testWaitGroup() {
	fmt.Println("\n--- Test 3: WaitGroup ---")
	
	var wg sync.WaitGroup
	
	for i := 1; i <= 3; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			fmt.Printf("Worker %d starting\n", id)
			time.Sleep(100 * time.Millisecond)
			fmt.Printf("Worker %d done\n", id)
		}(i)
	}
	
	wg.Wait()
	fmt.Println("All workers completed")
}

func testDefer() {
	fmt.Println("\n--- Test 4: Defer ---")
	
	fmt.Println("Start")
	defer fmt.Println("Deferred 1")
	defer fmt.Println("Deferred 2")
	defer fmt.Println("Deferred 3")
	fmt.Println("End")
}

// Custom type
type Person struct {
	Name string
	Age  int
}

// Method on Person
func (p Person) Greet() {
	fmt.Printf("Hello, I'm %s and I'm %d years old\n", p.Name, p.Age)
}

// Pointer method
func (p *Person) HaveBirthday() {
	p.Age++
	fmt.Printf("%s is now %d years old\n", p.Name, p.Age)
}

func testStructs() {
	fmt.Println("\n--- Test 5: Structs and Methods ---")
	
	person := Person{
		Name: "Alice",
		Age:  25,
	}
	
	person.Greet()
	person.HaveBirthday()
	person.Greet()
}

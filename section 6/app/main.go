package main

import (
	"fmt"
	"log"
	"net/http"
)

func helloHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Received request from %s", r.RemoteAddr)
	fmt.Fprintln(w, "Hello from a reproducible Go multi-stage build!")
}

func main() {
	http.HandleFunc("/", helloHandler)
	log.Println("Starting web server on port 8080...")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

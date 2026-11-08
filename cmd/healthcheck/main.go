package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	url := "http://" + os.Getenv("HTTP_ADDR") + "/health"

	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	resp, err := client.Get(url)
	if err != nil {
		fmt.Fprintln(os.Stderr, "health check failed:", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "health check failed: status %d\n", resp.StatusCode)
		os.Exit(1)
	}
}

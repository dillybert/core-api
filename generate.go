package main

//go:generate go tool ogen --target generated/ogen -package ogen --clean openapi.yaml
//go:generate go tool sqlc generate

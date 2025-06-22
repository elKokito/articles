---
layout: post
title: genai function call
categories: [golang, ai, gemini]
tags: [golang, ai, gemini]
---

## Automating Workflows: Function Calling with JSON Schema

Function calling allows you to bridge the gap between natural language and your existing Go code. Instead of just generating text, you can empower the model to request the execution of specific functions you've defined in your application. The model determines *which* function to call and with *what arguments* based on the user's prompt.

This is the key to building powerful automations. You can define functions that interact with your cloud provider, your CI/CD system, your monitoring platform, or any internal API.

### The Function Calling Flow

The process involves a conversation between your code and the model:

1.  **You Define the Tools**: In your Go code, you define a `genai.Tool` which contains one or more `genai.FunctionDeclaration` structs. Each declaration tells the model about a function you have: its name, what it does, and what parameters it accepts.
2.  **Model Receives a Prompt**: The user sends a prompt, like "What's the status of the 'api-gateway' service in the 'production' namespace?". You send this prompt to the model along with the list of available tools.
3.  **Model Returns a Function Call**: Instead of answering directly, the model recognizes that it needs more information. It returns a `*genai.FunctionCall` object. This object is a JSON structure containing the name of the function it wants to run (e.g., `getKubeServiceStatus`) and the arguments it has extracted from the prompt (e.g., `{"namespace": "production", "serviceName": "api-gateway"}`).
4.  **You Execute the Function**: Your Go code receives this `FunctionCall`, parses the arguments, and executes your *actual* Go function (e.g., a function that uses the Kubernetes client-go library to check the service status).
5.  **You Return the Result**: You take the output from your function (e.g., "Service is running with 3/3 pods ready") and send it back to the model in a new API call, this time as a `*genai.FunctionResponse`.
6.  **Model Generates the Final Answer**: The model now has the context of the original question *and* the data from your tool. It uses this information to generate a final, user-friendly, natural language response, like "The 'api-gateway' service in the 'production' namespace is healthy and currently running with 3 out of 3 pods ready."

### How JSON Schema Fits In

The crucial part of this process is step \#1: defining your function's parameters. You do this using a `*genai.Schema`, just like you did for enforcing JSON output. This schema defines the "contract" for the function's arguments.

When you declare a function, the `Parameters` field of the `FunctionDeclaration` is a `*genai.Schema` that describes the expected arguments as a JSON object. This ensures that when the model decides to call your function, the arguments it provides will be in a predictable, structured format that your Go code can easily parse.

### DevOps Use Case: A Kubernetes Service Status Checker

Let's build a command-line tool that allows a user to ask for the status of a Kubernetes service in natural language. Our tool will define a function that can check this status, and the model will call it when needed.

### Code Example: Function Calling in Action

```go
package main

import (
  "context"
  "encoding/json"
  "fmt"
  "log"
  "os"

  "google.golang.org/genai"
)

// getKubeServiceStatus is our actual Go function that simulates checking a service status.
// In a real application, this would use the Kubernetes client-go library to interact with a cluster.
func getKubeServiceStatus(namespace, serviceName string) (string, error) {
  fmt.Printf("[Executing function: getKubeServiceStatus(namespace: %s, serviceName: %s)]\n", namespace, serviceName)
  // Simulate checking the service
  if namespace == "production" && serviceName == "api-gateway" {
	return `{"status": "Healthy", "ready_pods": 3, "total_pods": 3}`, nil
  }
  if namespace == "staging" && serviceName == "user-db" {
	return `{"status": "Degraded", "ready_pods": 0, "total_pods": 1, "error": "CrashLoopBackOff"}`, nil
  }
  return "", fmt.Errorf("service '%s' in namespace '%s' not found", serviceName, namespace)
}

func main() {
  ctx := context.Background()
  apiKey := os.Getenv("GEMINI_API_KEY")
  if apiKey == "" {
	log.Fatal("GEMINI_API_KEY environment variable not set")
  }

  client, err := genai.NewClient(ctx, &genai.ClientConfig{
	APIKey:  apiKey,
	Backend: genai.BackendGeminiAPI,
  })
  if err != nil {
	log.Fatalf("Failed to create client: %v", err)
  }
  defer client.Close()

  model := "gemini-1.5-pro-latest"

  // 1. Define the function declaration and the schema for its parameters.
  // This tells the model about the tool it can use.
  getKubeServiceStatusDecl := &genai.FunctionDeclaration{
	Name:        "getKubeServiceStatus",
	Description: "Get the status of a specific service in a Kubernetes cluster.",
	Parameters: &genai.Schema{
	  Type: genai.TypeObject,
	  Properties: map[string]*genai.Schema{
		"namespace": {
		  Type:        genai.TypeString,
		  Description: "The Kubernetes namespace of the service.",
		},
		"serviceName": {
		  Type:        genai.TypeString,
		  Description: "The name of the service.",
		},
	  },
	  Required: []string{"namespace", "serviceName"},
	},
  }

  // Add the function declaration to a Tool.
  tools := []*genai.Tool{
	{FunctionDeclarations: []*genai.FunctionDeclaration{getKubeServiceStatusDecl}},
  }

  // 2. Send the initial prompt and the available tools to the model.
  fmt.Println("You: What's the status of the 'api-gateway' service in the 'production' namespace?")
  prompt := "What's the status of the 'api-gateway' service in the 'production' namespace?"
  resp, err := client.Models.GenerateContent(ctx, model, genai.Text(prompt), &genai.GenerateContentConfig{Tools: tools})
  if err != nil {
	log.Fatalf("Initial generation failed: %v", err)
  }

  // 3. Check if the model returned a function call.
  if len(resp.FunctionCalls()) == 0 {
	log.Fatalf("Expected a function call, but got none. Response: %s", resp.Text())
  }

  fc := resp.FunctionCalls()[0]
  fmt.Printf("Model wants to call function: %s with args: %v\n", fc.Name, fc.Args)

  if fc.Name != "getKubeServiceStatus" {
	log.Fatalf("Unexpected function call: %s", fc.Name)
  }

  // 4. Execute the function with the arguments provided by the model.
  namespace, ok1 := fc.Args["namespace"].(string)
  serviceName, ok2 := fc.Args["serviceName"].(string)
  if !ok1 || !ok2 {
	log.Fatalf("Could not parse function call arguments: %v", fc.Args)
  }

  status, err := getKubeServiceStatus(namespace, serviceName)
  if err != nil {
	log.Fatalf("Function execution failed: %v", err)
  }

  // 5. Send the function's result back to the model.
  fmt.Printf("[Sending function response to model: %s]\n", status)
  var functionResponse map[string]any
  if err := json.Unmarshal([]byte(status), &functionResponse); err != nil {
	log.Fatalf("Failed to unmarshal function response: %v", err)
  }

  // Construct the conversation history, including the model's initial function call request
  // and our function response.
  conversationHistory := []*genai.Content{
	{Parts: []*genai.Part{genai.NewPartFromText(prompt)}, Role: "user"},
	{Parts: []*genai.Part{genai.NewPartFromFunctionCall(fc.Name, fc.Args)}, Role: "model"},
	{Parts: []*genai.Part{genai.NewPartFromFunctionResponse(fc.Name, functionResponse)}, Role: "user"},
  }

  finalResp, err := client.Models.GenerateContent(ctx, model, conversationHistory, &genai.GenerateContentConfig{Tools: tools})
  if err != nil {
	log.Fatalf("Final generation failed: %v", err)
  }

  // 6. The model now generates a natural language response based on the function's output.
  fmt.Println("\nModel's Final Answer:")
  fmt.Println(finalResp.Text())
}
```

This example clearly illustrates the power of combining natural language understanding with structured function execution. The JSON schema in the `FunctionDeclaration` is the critical piece that ensures the data passed between the model and your Go code is reliable, predictable, and easy to work with, forming the foundation for robust DevOps automation.

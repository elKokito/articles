---
layout: post
title: genai json schema
categories: [golang, ai, gemini]
tags: [golang, ai, gemini]
---

## Structured Outputs: Mastering JSON and Schema Enforcement

In DevOps, automation is king. The ability to reliably produce structured data is not just a convenience; it's a necessity for building robust, predictable pipelines and tools. The Google Gen AI Go SDK provides powerful features to ensure that the model's output is not just a freeform string of text, but a well-structured, machine-readable JSON object that conforms to a schema you define.

This capability is a game-changer for automating tasks like generating configuration files, summarizing monitoring data into a structured format, or creating consistent metadata for infrastructure resources.

There are two primary ways to achieve JSON output:

1.  **Requesting JSON Output**: A simple hint to the model to format its response as JSON.
2.  **Enforcing a JSON Schema**: A powerful constraint that forces the model's output to adhere to a specific JSON structure you define.

### How It Works: `ResponseMIMEType` and `ResponseSchema`

The magic happens within the `GenerateContentConfig` struct, which is passed to the `client.Models.GenerateContent` method. Two fields are key here:

  * **`ResponseMIMEType`**: When you set this field to `"application/json"`, you are telling the model that you expect its output to be a JSON-formatted string. This is the first and most basic step.
  * **`ResponseSchema`**: This is where you define the *exact* structure of the JSON you want. You provide a `*genai.Schema` object that describes the properties, types, and descriptions of the desired JSON. When this is set, the model is **constrained** to produce output that strictly follows this schema. This provides a strong guarantee of a predictable and parsable response.

### Use Case: Automated Microservice Configuration

Imagine you're building a CLI tool for your platform engineering team. A developer should be able to describe a new microservice in plain English, and your tool should generate a valid, structured JSON configuration file that can be fed into your deployment pipeline (e.g., to generate a Kubernetes manifest).

**The goal:** Take a natural language request like *"Create a config for a 'user-auth' service on port 8080 with 3 replicas and a 'production' environment."* and reliably produce the following JSON:

```json
{
  "service_name": "user-auth",
  "port": 8080,
  "replicas": 3,
  "env_vars": [
    {
      "key": "ENVIRONMENT",
      "value": "production"
    }
  ]
}
```

Without a schema, the model might name the fields differently (`serviceName`, `replica_count`, etc.), use strings for numbers, or omit fields entirely, making automation impossible. By enforcing a schema, we can guarantee the output's structure.

### Code Example: Enforcing a JSON Schema

Let's build the Go application for this use case.

1.  **Define the Go Struct:** First, we define a Go struct that represents our target JSON structure. This will make it easy to unmarshal the model's response.

    ```go
    // ServiceConfig represents the structured configuration for a microservice.
    type ServiceConfig struct {
        ServiceName string    `json:"service_name"`
        Port        int       `json:"port"`
        Replicas    int       `json:"replicas"`
        EnvVars     []EnvVar  `json:"env_vars"`
    }

    // EnvVar represents a single environment variable.
    type EnvVar struct {
        Key   string `json:"key"`
        Value string `json:"value"`
    }
    ```

2.  **Define the `genai.Schema`:** Next, we create a `*genai.Schema` object that describes this structure to the model. This is the most critical step.

    ```go
    // Define the schema for the environment variable object.
    envVarSchema := &genai.Schema{
        Type: genai.TypeObject,
        Properties: map[string]*genai.Schema{
            "key":   {Type: genai.TypeString, Description: "The environment variable key."},
            "value": {Type: genai.TypeString, Description: "The environment variable value."},
        },
    }

    // Define the main schema for the service configuration.
    serviceConfigSchema := &genai.Schema{
        Type:        genai.TypeObject,
        Description: "Configuration for a microservice.",
        Properties: map[string]*genai.Schema{
            "service_name": {Type: genai.TypeString, Description: "The name of the microservice."},
            "port":         {Type: genai.TypeInteger, Description: "The port the service will listen on."},
            "replicas":     {Type: genai.TypeInteger, Description: "The number of replicas for the service."},
            "env_vars": {
                Type:        genai.TypeArray,
                Description: "A list of environment variables.",
                Items:       envVarSchema, // Nest the EnvVar schema here
            },
        },
        Required: []string{"service_name", "port", "replicas"},
    }
    ```

    Notice how the schema definition mirrors the JSON structure, specifying the `Type` for each field and providing a `Description` to help the model understand the purpose of each field. We also use `Required` to indicate which fields are mandatory.

3.  **Putting It All Together:** Now, we write the main application logic.

<!-- end list -->

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

// ServiceConfig represents the structured configuration for a microservice.
type ServiceConfig struct {
	ServiceName string   `json:"service_name"`
	Port        int      `json:"port"`
	Replicas    int      `json:"replicas"`
	EnvVars     []EnvVar `json:"env_vars"`
}

// EnvVar represents a single environment variable.
type EnvVar struct {
	Key   string `json:"key"`
	Value string `json:"value"`
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

	// --- Define the Schema ---
	envVarSchema := &genai.Schema{
		Type: genai.TypeObject,
		Properties: map[string]*genai.Schema{
			"key":   {Type: genai.TypeString},
			"value": {Type: genai.TypeString},
		},
	}

	serviceConfigSchema := &genai.Schema{
		Type:        genai.TypeObject,
		Description: "Configuration for a microservice.",
		Properties: map[string]*genai.Schema{
			"service_name": {Type: genai.TypeString, Description: "The name of the microservice, e.g., 'user-auth' or 'order-processing'."},
			"port":         {Type: genai.TypeInteger, Description: "The network port the service will listen on."},
			"replicas":     {Type: genai.TypeInteger, Description: "The number of replicas for the service deployment."},
			"env_vars": {
				Type:        genai.TypeArray,
				Description: "A list of key-value environment variables.",
				Items:       envVarSchema,
			},
		},
		Required: []string{"service_name", "port", "replicas"},
	}

	// --- Configure the Model Call ---
	config := &genai.GenerateContentConfig{
		ResponseMIMEType: "application/json",
		ResponseSchema:   serviceConfigSchema,
	}

	prompt := "Generate a service config for a 'user-auth' service running on port 8080 with 3 replicas and an 'ENVIRONMENT' variable set to 'production'."

	// --- Generate the Structured Content ---
	resp, err := client.Models.GenerateContent(ctx, model, genai.Text(prompt), config)
	if err != nil {
		log.Fatalf("Failed to generate content: %v", err)
	}

	fmt.Println("--- Raw JSON Response from Model ---")
	rawJSON := resp.Text()
	fmt.Println(rawJSON)

	// --- Unmarshal the JSON into our Go struct ---
	var serviceConf ServiceConfig
	err = json.Unmarshal([]byte(rawJSON), &serviceConf)
	if err != nil {
		log.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	fmt.Println("\n--- Unmarshaled Go Struct ---")
	fmt.Printf("Service Name: %s\n", serviceConf.ServiceName)
	fmt.Printf("Port: %d\n", serviceConf.Port)
	fmt.Printf("Replicas: %d\n", serviceConf.Replicas)
	for _, env := range serviceConf.EnvVars {
		fmt.Printf("Env Var: %s=%s\n", env.Key, env.Value)
	}
}
```

When you run this code, the output will be a valid JSON string that can be perfectly unmarshaled into the `ServiceConfig` struct. This demonstrates how you can move from unreliable text parsing to guaranteed, structured data, making your DevOps automations more predictable and resilient.

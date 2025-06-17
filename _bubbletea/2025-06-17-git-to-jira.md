---
layout: post
title: git-to-jira
categories: [llm, bubbletea, jira]
tags: [llm, bubbletea, jira]
---
# Building a "Git-to-Jira" TUI with Go, Bubble Tea, and AI


### Introduction

In modern software development, the cycle of coding, creating a pull request, and documenting work in a project management tool like Jira is a daily ritual. However, this process is often fragmented, forcing developers to constantly switch contexts between their code editor, the GitHub web interface, and their Jira board. This "workflow friction" is more than a minor annoyance; it's a drain on productivity and focus. Each step—crafting a PR title, writing a description, navigating to Jira, creating a new ticket, and copying over the details—is a manual, repetitive task ripe for human error and a significant source of cognitive load.

This article presents an elegant, automated solution: a command-line tool that streamlines this entire workflow into a single, interactive command. We will build a "Git-to-Jira" Text-based User Interface (TUI) tool that automates the creation of a GitHub pull request and a corresponding, detailed Jira ticket. The core of this tool's intelligence lies in its ability to use a Large Language Model (LLM) to generate high-quality, context-aware titles and descriptions directly from the code changes in a `git diff`.

To build this powerful workflow accelerator, we will leverage a curated stack of modern technologies:

  * **Go**: Chosen for its performance, strong typing, and excellent support for building concurrent, single-binary command-line applications.[1]
  * **Bubble Tea**: A stateful TUI framework for Go, based on The Elm Architecture, that enables the creation of sophisticated and responsive terminal applications.[2, 3]
  * **GitHub & Jira REST APIs**: We will programmatically interact with these platforms to automate the creation of pull requests and issues.[4, 5]
  * **Large Language Models (LLM)**: By integrating with an LLM provider like OpenAI, we will transform raw `git diff` output into well-structured, human-readable documentation for our PRs and tickets.[6, 7]

## 1\. Core Architecture and Workflow

A robust command-line tool requires a well-defined architecture. Our Git-to-Jira tool is designed as a set of modular, interacting components orchestrated by a central TUI. This design promotes separation of concerns and maintainability.

### High-Level Architectural Overview

The application is composed of four primary components that communicate through a clear, event-driven flow:

  * **The TUI (Bubble Tea `Program`)**: This is the application's central nervous system. Built with the Bubble Tea framework, it is responsible for managing the application's state, rendering the user interface, and handling all user input. Crucially, it orchestrates the entire workflow by dispatching asynchronous tasks (as `tea.Cmd` functions) and reacting to the messages they produce upon completion. To maintain a responsive UI, the TUI's core `Update` loop never performs blocking I/O operations directly.[2, 8]
  * **Git Client Wrapper**: A dedicated module that encapsulates all interactions with the local Git repository. Its primary responsibility is to execute `git` commands, such as `git diff`, using Go's `os/exec` package and to parse their output.[9, 10]
  * **API Clients (GitHub, Jira, LLM)**: Three distinct clients, each isolated in its own module. Each client is responsible for the specifics of communicating with its respective external service: handling HTTP requests, managing authentication headers, and serializing/deserializing JSON data. This modularity makes the system easier to test and extend.[6, 11, 12]

The relationship between these components is not merely a simple sequence. The TUI acts as an **asynchronous orchestrator**. Any operation that involves I/O—fetching the git diff, calling the LLM, or posting to GitHub and Jira—is a potentially long-running, blocking task. If these tasks were executed directly within the TUI's main event loop, the entire interface would freeze, becoming unresponsive to user input. The architecture avoids this by using Bubble Tea's command-message pattern. The `Update` function dispatches a command (`tea.Cmd`), and the Bubble Tea runtime executes it in a separate goroutine. Once the task is complete, it sends a message (`tea.Msg`) back to the `Update` function, which can then update the application's state and trigger the next step. This makes the TUI the manager of a state machine, where transitions are driven by the completion of asynchronous events.

### End-to-End Workflow

The tool executes a precise sequence of events, managed by the TUI's state machine:

1.  **Invocation**: The user executes the compiled binary from their terminal within a Git repository's working directory.
2.  **State 1: Fetching Diff**: The Bubble Tea program initializes. Its `Init` function immediately returns a command to invoke our Git Client Wrapper to fetch the diff between the current branch and the remote main/master branch. The UI shows a loading spinner.
3.  **State 2: Generating Content**: The Git command completes and sends a `diffFetchedMsg` back to the TUI's `Update` function. The model's state transitions, and a new command is dispatched to the LLM Client, sending the diff string to generate a title and description. The spinner continues.
4.  **State 3: Awaiting User Approval**: The LLM API call returns a `contentGeneratedMsg`. The `Update` function stores the AI-generated title and description in the application's model. The `View` function now renders this content, presenting it to the user for review with "Approve" and "Cancel" options. The application is now idle, awaiting a `tea.KeyMsg` from the user.
5.  **State 4: Creating Pull Request**: If the user presses the approval key, the `Update` function dispatches a command to the GitHub API Client, passing the title and description to create a new pull request. The spinner reappears.
6.  **State 5: Creating Jira Ticket**: Upon successful PR creation, the GitHub client sends a `pullRequestCreatedMsg` containing the new PR's URL. The `Update` function immediately transitions state and dispatches a final command to the Jira API Client to create a corresponding ticket.
7.  **State 6: Final Status**: The Jira API call completes, sending a `jiraTicketCreatedMsg`. The `Update` function stores the final success status and the URLs for both the PR and the Jira ticket in the model. The `View` updates to display this summary information. The application then sends a `tea.Quit` command to exit gracefully.
8.  **Error Handling**: If any command at any stage fails (e.g., network error, invalid API key), it sends back a specific error message. The `Update` function catches this, transitions to an `error` state, and the `View` displays the error clearly to the user before exiting.

## 2\. Setting Up the Go Project

A solid foundation is key to any successful project. This section covers initializing the Go module, installing dependencies, and establishing a secure and flexible configuration management strategy.

### Initializing the Go Module

First, create a directory for the project and initialize it as a Go module. This is the standard practice for managing dependencies in modern Go development.[13, 14]bash
mkdir git-to-jira
cd git-to-jira
go mod init [github.com/your-username/git-to-jira](https://www.google.com/search?q=https://github.com/your-username/git-to-jira)

````

### Installing Dependencies

Our tool relies on several high-quality, open-source Go libraries. The following table outlines each dependency and its purpose in the project.

| Library | Import Path | Purpose |
| :--- | :--- | :--- |
| Bubble Tea | `github.com/charmbracelet/bubbletea` | The core framework for building our TUI.[2, 3] |
| Bubbles | `github.com/charmbracelet/bubbles` | A library of pre-built TUI components like spinners and text inputs.[15] |
| Lip Gloss | `github.com/charmbracelet/lipgloss` | A library for advanced terminal styling and layout, used to make our TUI look good.[16, 17] |
| Go GitHub | `github.com/google/go-github/vXX` | The official Go client library for interacting with the GitHub REST API.[11] |
| Go Jira | `github.com/andygrunwald/go-jira` | A widely-used Go client for the Jira REST API.[12, 18] |
| OpenAI Go | `github.com/openai/openai-go` | The official Go client for the OpenAI API, used for generating content.[6] |
| Viper | `github.com/spf13/viper` | A complete configuration solution for handling files, environment variables, and defaults.[19] |
| GoDotEnv | `github.com/joho/godotenv` | A utility to load environment variables from a `.env` file during local development.[20, 21] |

To install all these dependencies, run the following `go get` command. We specify a version for the `go-github` library to ensure API stability and reproducible builds.[11]

```bash
go get [github.com/charmbracelet/bubbletea](https://github.com/charmbracelet/bubbletea) \
       [github.com/charmbracelet/bubbles](https://github.com/charmbracelet/bubbles) \
       [github.com/charmbracelet/lipgloss](https://github.com/charmbracelet/lipgloss) \
       [github.com/google/go-github/v72](https://github.com/google/go-github/v72) \
       [github.com/andygrunwald/go-jira](https://github.com/andygrunwald/go-jira) \
       [github.com/openai/openai-go](https://github.com/openai/openai-go) \
       [github.com/spf13/viper](https://github.com/spf13/viper) \
       [github.com/joho/godotenv](https://github.com/joho/godotenv)
````

After running this, `go mod tidy` will finalize the `go.mod` and `go.sum` files.

### Secure Management of API Keys and Credentials

Hardcoding sensitive information like API keys directly into source code is a major security vulnerability and poor practice.[20] A professional application requires a layered configuration strategy that is both secure and flexible, accommodating different environments like local development and production CI/CD pipelines. We will use a combination of Viper and GoDotEnv to achieve this.

This approach effectively decouples the application from its environment. The application logic simply requests a configuration value, like `config.GetJiraToken()`, without needing to know whether that value comes from a file or an environment variable. This abstraction is a hallmark of the "12-Factor App" methodology, allowing the same compiled binary to be deployed across different environments without code changes.[19, 22]

1.  **`.env` for Local Development**: For local development, we will use a `.env` file to store our secrets. This file is easy to manage and **must** be added to your `.gitignore` file to prevent it from ever being committed to version control. The `godotenv` library will load these variables into the environment when the application starts.[20, 23]

    `.env` file example:

    ```
    GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
    JIRA_URL=[https://your-domain.atlassian.net](https://your-domain.atlassian.net)
    JIRA_USER=your-email@example.com
    JIRA_TOKEN=xxxxxxxxxxxxxxxxxxxx
    OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxx
    ```

2.  **Configuration File (`config.yaml`)**: Non-sensitive configuration, such as default values or user preferences, can be stored in a `config.yaml` file. This file can be committed to version control. Viper excels at reading and parsing structured configuration files.[24, 25]

    `config.yaml` file example:

    ```yaml
    git:
      remote: "origin"
      basebranch: "main"
    jira:
      projectkey: "PROJ"
      issuetype: "Task"
    llm:
      model: "gpt-4o"
    ```

3.  **Environment Variables for Production**: In a production or CI/CD environment, secrets should be injected as environment variables. Viper is designed to seamlessly read these variables, and they will automatically override any values defined in the configuration file, following a clear order of precedence.[19]

Here is a `config.go` file that centralizes all configuration logic:

```go
package config

import (
	"fmt"
	"[github.com/joho/godotenv](https://github.com/joho/godotenv)"
	"[github.com/spf13/viper](https://github.com/spf13/viper)"
	"log"
)

// Config stores all configuration of the application.
// The values are read by viper from a config file or environment variables.
type Config struct {
	GitHubToken   string `mapstructure:"GITHUB_TOKEN"`
	JiraURL       string `mapstructure:"JIRA_URL"`
	JiraUser      string `mapstructure:"JIRA_USER"`
	JiraToken     string `mapstructure:"JIRA_TOKEN"`
	OpenAIAPIKey  string `mapstructure:"OPENAI_API_KEY"`
	GitRemote     string `mapstructure:"GIT_REMOTE"`
	GitBaseBranch string `mapstructure:"GIT_BASE_BRANCH"`
	JiraProjectKey string `mapstructure:"JIRA_PROJECT_KEY"`
	JiraIssueType string `mapstructure:"JIRA_ISSUE_TYPE"`
	LLMModel      string `mapstructure:"LLM_MODEL"`
}

// LoadConfig reads configuration from file and environment variables.
func LoadConfig() (config Config, err error) {
	// Load.env file for local development. In production, env vars are set directly.
	if err := godotenv.Load(); err!= nil {
		log.Println("No.env file found, reading from environment")
	}

	// Set default values
	viper.SetDefault("GIT_REMOTE", "origin")
	viper.SetDefault("GIT_BASE_BRANCH", "main")
	viper.SetDefault("JIRA_ISSUE_TYPE", "Task")
	viper.SetDefault("LLM_MODEL", "gpt-4o")

	// Tell viper to look for a config file named `config` in the current directory
	viper.AddConfigPath(".")
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")

	// Attempt to read the config file, ignoring errors if it's not found
	if err := viper.ReadInConfig(); err!= nil {
		if _, ok := err.(viper.ConfigFileNotFoundError);!ok {
			return Config{}, fmt.Errorf("error reading config file: %w", err)
		}
	}

	// Enable viper to read environment variables
	viper.AutomaticEnv()

	// Unmarshal the configuration into our struct
	err = viper.Unmarshal(&config)
	return
}
```

## 3\. Interacting with Git: Getting the Diff

The foundational input for our AI content generation is the `git diff`. We need a reliable way to execute the `git diff` command from within our Go application and capture its output. This is accomplished using the standard library's `os/exec` package.

A critical detail when working with the `diff` command (and by extension, `git diff`) is its use of exit codes. A successful execution of `diff` does not always return an exit code of `0`. The exit codes are specifically defined [9]:

  * **Exit Code 0**: No differences were found.
  * **Exit Code 1**: Differences were found.
  * **Exit Code \> 1**: An error occurred during execution.

A naive check like `if err!= nil` after running the command will fail. Go's `exec` package treats any non-zero exit code as an error of type `*exec.ExitError`.[10] Therefore, an exit code of `1`—which for our purposes is a success—would be incorrectly interpreted as a fatal error.

The correct, robust approach is to inspect the error more closely. We must check if the returned error is an `*exec.ExitError` and, if so, extract the underlying system exit code to specifically allow `1` as a valid, non-error state.[9]

The following function, `getGitDiff`, demonstrates this robust implementation. It constructs the `git diff` command to compare the current branch (`HEAD`) against a remote base branch (e.g., `origin/main`) and correctly handles the exit codes.

```go
package git

import (
	"fmt"
	"os/exec"
	"syscall"
)

// getGitDiff executes `git diff` to get the changes between the current branch
// and the specified remote base branch. It correctly handles the exit codes
// from the diff command.
func getGitDiff(remoteName, baseBranch string) (string, error) {
	// The '...' syntax in git diff is important. It shows the diff between
	// the tip of the current branch and the common ancestor with 'remote/base'.
	target := fmt.Sprintf("%s/%s...", remoteName, baseBranch)
	cmd := exec.Command("git", "diff", target)

	// We use CombinedOutput to capture both stdout and stderr. This is useful
	// for logging the full error message if git fails for reasons other than
	// finding a diff.
	output, err := cmd.CombinedOutput()

	if err!= nil {
		// Check if the error is an ExitError
		if exitErr, ok := err.(*exec.ExitError); ok {
			// The command exit with a non-zero status.
			// This is expected for `git diff` which returns 1 for differences.
			if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
				// Exit status 1 means differences were found. This is a success case for us.
				if status.ExitStatus() == 1 {
					return string(output), nil
				}
				// Any other exit status is a genuine error.
				return "", fmt.Errorf("git diff exited with status %d: %s", status.ExitStatus(), string(output))
			}
		}
		// This was not an ExitError, but some other error (e.g., command not found).
		return "", fmt.Errorf("failed to execute git diff: %w, output: %s", err, string(output))
	}

	// If err is nil, it means exit code was 0, so no differences were found.
	// We return an empty string and no error.
	return string(output), nil
}
```

## 4\. Generating Content with an LLM

With the `git diff` in hand, we can now leverage a Large Language Model (LLM) to automate the tedious task of writing a pull request title and description. The key to getting reliable, useful output from an LLM is **prompt engineering**.

### Prompt Engineering for Structured Output

Simply asking an LLM to "summarize this diff" can yield inconsistent results that are difficult to parse programmatically. A more professional approach is to instruct the model to return its response in a structured format, such as JSON. This ensures the output is predictable and can be easily unmarshaled into a Go struct.

Here is a well-crafted prompt template designed for this task. It clearly defines the context, the required output format, and the input data.

```
Based on the following git diff, please generate a concise pull request title and a structured, detailed description. The description should be in Markdown format and include a summary of changes and a "How to Test" section.

Return your response as a single JSON object with two keys: "title" and "description".

--- GIT DIFF ---
{{.Diff}}
```

### Interacting with the OpenAI API

We will use the official `openai-go` library to communicate with the OpenAI API.[6] The library simplifies the process of making authenticated requests and handling responses. The client can be configured to automatically read the `OPENAI_API_KEY` from the environment, which we set up in our configuration section.[6]

The core of the interaction is creating a `ChatCompletionRequest`. We specify the model we want to use (e.g., `gpt-4o`), the role of the message (`user`), and the content, which will be our formatted prompt.[26, 27]

The function below, `generateContent`, encapsulates this entire process.

```go
package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"[github.com/openai/openai-go](https://github.com/openai/openai-go)"
)

// ContentResponse defines the structure for the JSON response from the LLM.
type ContentResponse struct {
	Title       string `json:"title"`
	Description string `json:"description"`
}

// generateContent sends the git diff to the OpenAI API and asks for a PR title
// and description in a structured JSON format.
func generateContent(diff string, apiKey string, model string) (string, string, error) {
	if apiKey == "" {
		return "", "", fmt.Errorf("OpenAI API key is not configured")
	}

	client := openai.NewClient(openai.WithKey(apiKey))
	ctx := context.Background()

	prompt := fmt.Sprintf(`
Based on the following git diff, please generate a concise pull request title and a structured, detailed description. The description should be in Markdown format and include a summary of changes and a "How to Test" section.

Return your response as a single JSON object with two keys: "title" and "description".

--- GIT DIFF ---
%s
`, diff)

	messages :=openai.ChatCompletionMessageParamUnion{
		openai.UserMessage(prompt),
	}

	params := openai.ChatCompletionNewParams{
		Model:    model,
		Messages: messages,
	}

	resp, err := client.Chat.Completions.New(ctx, params)
	if err!= nil {
		return "", "", fmt.Errorf("chat completion request failed: %w", err)
	}

	if len(resp.Choices) == 0 |
| resp.Choices.Message.Content == "" {
		return "", "", fmt.Errorf("received an empty response from OpenAI API")
	}

	var contentResp ContentResponse
	err = json.Unmarshal(byte(resp.Choices.Message.Content), &contentResp)
	if err!= nil {
		// Fallback if JSON parsing fails
		return "AI-Generated Content", resp.Choices.Message.Content, nil
	}

	return contentResp.Title, contentResp.Description, nil
}
```

## 5\. The Bubble Tea TUI: State Management

The heart of our interactive tool is the Text-based User Interface (TUI), built with Bubble Tea. This framework is based on The Elm Architecture, a functional design pattern that is exceptionally well-suited for managing state in interactive applications.[2, 3]

### Core Concepts of The Elm Architecture

A Bubble Tea program is structured around three key methods defined on a `Model` [3]:

  * **`Model`**: A struct that holds the entire state of the application. It is the single source of truth.
  * **`Init`**: A function that is called once when the program starts. It returns an initial `tea.Cmd` to perform any startup I/O.
  * **`Update`**: The state transition function. It is called whenever an event (`tea.Msg`) occurs (like a keypress or a response from an API call). It processes the message, updates the model, and can return another `tea.Cmd` to trigger subsequent actions.
  * **`View`**: A function that takes the current `Model` and returns a `string` representing the UI to be rendered on the screen.

### Defining the Application State (`Model`)

Our `Model` struct must be comprehensive enough to track every piece of information required throughout the tool's lifecycle. This includes not just UI elements like a spinner, but also the application's current state, data fetched from services, and any errors that occur. We use an `enum` for the `state` to create a clear and manageable state machine.

```go
package main

import (
	"[github.com/charmbracelet/bubbles/spinner](https://github.com/charmbracelet/bubbles/spinner)"
	tea "[github.com/charmbracelet/bubbletea](https://github.com/charmbracelet/bubbletea)"
)

// state represents the current step in our workflow.
type state int

const (
	stateFetchingDiff state = iota
	stateGeneratingContent
	stateReadyForApproval
	stateCreatingPR
	stateCreatingJiraTicket
	stateDone
	stateError
)

// Model holds the application's complete state.
type Model struct {
	state         state
	spinner       spinner.Model
	err           error
	gitDiff       string
	prTitle       string
	prDescription string
	prURL         string
	jiraURL       string
	// Add other fields like config here
}
```

### The `Update` Function as a State Machine

The `Update` function is the engine of our application. It acts as a state machine, routing logic based on two factors: the current application state (`m.state`) and the type of the incoming message (`tea.Msg`). This is typically implemented as a nested `switch` statement.

```go
// A skeleton of the Update function demonstrating the state machine structure.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        // Handle global key presses like 'q' or 'ctrl+c' to quit.
        // Also handle context-specific keys based on m.state.
        switch msg.String() {
        case "q", "ctrl+c":
            return m, tea.Quit
        }
    
    // Custom messages from our commands
    case diffFetchedMsg:
        // Logic for when the git diff is ready
    case contentGeneratedMsg:
        // Logic for when the LLM content is ready
    //... other custom message types
    }

    // Handle spinner animation
    var cmd tea.Cmd
    m.spinner, cmd = m.spinner.Update(msg)
    return m, cmd
}
```

### The Power of `tea.Cmd` for Asynchronous I/O

As established in the architecture section, `tea.Cmd` is the mechanism for performing blocking I/O without freezing the UI.[8, 28] A `tea.Cmd` is simply a function that returns a `tea.Msg`. The Bubble Tea runtime executes this function in a background goroutine. When the function completes, its return value (the `tea.Msg`) is sent back to the `Update` loop for processing. This event-driven cycle keeps the application responsive at all times.

The following table visualizes the application's state-transition logic, showing how states, commands, and messages are chained together to form the complete workflow.

| Current State (`m.state`) | Triggering `tea.Cmd` (Initiates Action) | Completion `tea.Msg` (Signals Result) | Next State |
| :--- | :--- | :--- | :--- |
| `stateFetchingDiff` | `getGitDiffCmd()` | `diffFetchedMsg{}` or `errorMsg{}` | `stateGeneratingContent` or `stateError` |
| `stateGeneratingContent` | `generateContentCmd()` | `contentGeneratedMsg{}` or `errorMsg{}` | `stateReadyForApproval` or `stateError` |
| `stateReadyForApproval` | (User Input: `tea.KeyMsg`) | `createPRMsg{}` | `stateCreatingPR` |
| `stateCreatingPR` | `createPRCmd()` | `prCreatedMsg{}` or `errorMsg{}` | `stateCreatingJiraTicket` or `stateError` |
| `stateCreatingJiraTicket` | `createJiraTicketCmd()` | `jiraTicketCreatedMsg{}` or `errorMsg{}` | `stateDone` or `stateError` |
| `stateDone` / `stateError` | `tea.Quit` | (None) | (Exit) |

## 6\. Integrating with GitHub and Jira

To automate our workflow, we need to create self-contained functions that interact with the GitHub and Jira APIs. Encapsulating this logic into dedicated functions improves modularity and makes our main TUI logic cleaner.

### Opening a Pull Request with `go-github`

We will use the `go-github` library to create a pull request. Authentication is handled by providing a GitHub Personal Access Token (PAT) as an OAuth2 token.[11] The `PullRequests.Create` method is the core of this operation. It requires a `NewPullRequest` struct, where we must provide the `Title`, `Body`, `Head` (the feature branch), and `Base` (the target branch). Note that the fields in this struct are pointers, so we use the `github.String()` helper to convert our string literals.[11]

```go
package github

import (
	"context"
	"fmt"
	"[github.com/google/go-github/v72/github](https://github.com/google/go-github/v72/github)"
	"golang.org/x/oauth2"
)

// createPullRequest creates a new pull request on GitHub.
func createPullRequest(token, owner, repo, title, description, headBranch, baseBranch string) (string, error) {
	ctx := context.Background()
	ts := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: token},
	)
	tc := oauth2.NewClient(ctx, ts)
	client := github.NewClient(tc)

	newPR := &github.NewPullRequest{
		Title: github.String(title),
		Body:  github.String(description),
		Head:  github.String(headBranch),
		Base:  github.String(baseBranch),
	}

	pr, _, err := client.PullRequests.Create(ctx, owner, repo, newPR)
	if err!= nil {
		return "", fmt.Errorf("failed to create pull request: %w", err)
	}

	return pr.GetHTMLURL(), nil
}
```

### Creating a Jira Ticket with `go-jira`

For Jira integration, we use the `go-jira` library. Authentication for Jira Cloud is typically done with a user's email address and an API Token generated from their Atlassian account settings.[18, 29, 30] The `Issue.Create` method takes a `jira.Issue` struct. We populate the `Fields` of this struct with the necessary information: `Project` (by its key), `IssueType` (by name), `Summary` (the title), and `Description`.[31, 32]

```go
package jira

import (
	"fmt"
	"[github.com/andygrunwald/go-jira](https://github.com/andygrunwald/go-jira)"
)

// createJiraTicket creates a new issue in a Jira project.
func createJiraTicket(jiraURL, user, token, title, description, projectKey, issueType string) (string, error) {
	tp := jira.BasicAuthTransport{
		Username: user,
		Password: token,
	}

	client, err := jira.NewClient(tp.Client(), jiraURL)
	if err!= nil {
		return "", fmt.Errorf("failed to create Jira client: %w", err)
	}

	issueFields := &jira.IssueFields{
		Project: jira.Project{
			Key: projectKey,
		},
		Summary:     title,
		Description: description,
		Type: jira.IssueType{
			Name: issueType,
		},
	}

	issue := jira.Issue{
		Fields: issueFields,
	}

	newIssue, _, err := client.Issue.Create(&issue)
	if err!= nil {
		return "", fmt.Errorf("failed to create Jira ticket: %w", err)
	}

	// The URL to the newly created issue
	ticketURL := fmt.Sprintf("%s/browse/%s", jiraURL, newIssue.Key)
	return ticketURL, nil
}
```

## 7\. Bringing It All Together in the Update Function

With all the building blocks in place—Git interaction, LLM content generation, and API clients—we can now assemble the complete `Update` function. This function is the heart of the TUI, orchestrating the entire workflow by handling messages and managing state transitions. The following code is a detailed, commented implementation that demonstrates the full, event-driven flow.

```go
// This is a simplified but functional version of the main Update function.
// It shows how messages from commands drive the state machine.

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	// Handle key presses from the user
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "y", "enter":
			// If we are in the approval state, 'y' or 'enter' triggers the next step.
			if m.state == stateReadyForApproval {
				m.state = stateCreatingPR
				m.statusMessage = "Creating pull request..."
				// Return a command to create the pull request.
				return m, createPRCmd(m.config, m.prTitle, m.prDescription)
			}
		}

	// Handle the completion of the `getGitDiff` command
	case diffFetchedMsg:
		if msg.err!= nil {
			m.err = msg.err
			m.state = stateError
			return m, tea.Quit
		}
		if msg.diff == "" {
			m.statusMessage = "No git diff found. Nothing to do."
			m.state = stateDone
			return m, tea.Quit
		}
		m.gitDiff = msg.diff
		m.state = stateGeneratingContent
		m.statusMessage = "Generating title and description with AI..."
		// Now, return a command to generate content with the LLM.
		return m, generateContentCmd(m.config, m.gitDiff)

	// Handle the completion of the LLM content generation
	case contentGeneratedMsg:
		if msg.err!= nil {
			m.err = msg.err
			m.state = stateError
			return m, tea.Quit
		}
		m.prTitle = msg.title
		m.prDescription = msg.description
		m.state = stateReadyForApproval
		// No command is returned here; we wait for user input.
		return m, nil

	// Handle the completion of the pull request creation
	case prCreatedMsg:
		if msg.err!= nil {
			m.err = msg.err
			m.state = stateError
			return m, tea.Quit
		}
		m.prURL = msg.url
		m.state = stateCreatingJiraTicket
		m.statusMessage = "Pull request created! Creating Jira ticket..."
		// Immediately return a command to create the Jira ticket.
		return m, createJiraTicketCmd(m.config, m.prTitle, m.prDescription)

	// Handle the completion of the Jira ticket creation
	case jiraTicketCreatedMsg:
		if msg.err!= nil {
			m.err = msg.err
			m.state = stateError
			return m, tea.Quit
		}
		m.jiraURL = msg.url
		m.state = stateDone
		m.statusMessage = "All done!"
		// The workflow is complete, so we quit.
		return m, tea.Quit

	// Handle any generic error message from our commands
	case errorMsg:
		m.err = msg.err
		m.state = stateError
		return m, tea.Quit
	}

	// Update the spinner animation on every tick
	var cmd tea.Cmd
	m.spinner, cmd = m.spinner.Update(msg)
	return m, cmd
}
```

This implementation clearly shows the reactive nature of the application. The `Update` function does not contain a linear script; instead, it responds to a series of events, each one triggering the next logical step in the workflow. The robust error handling ensures that if any step fails, the application captures the error, updates its state accordingly, and provides clear feedback to the user instead of crashing.

## Conclusion

By following this guide, a developer can construct a sophisticated and genuinely useful CLI tool that directly addresses a common point of friction in the software development lifecycle. We have built more than just a script; we have engineered a robust, AI-augmented workflow accelerator. The final product consolidates a multi-step, multi-application process into a single, fluid command, saving time and reducing the cognitive overhead of context switching.

The key achievements and architectural principles demonstrated include:

  * **Asynchronous Orchestration**: Leveraging Bubble Tea's command-message pattern to build a responsive, non-blocking TUI that orchestrates multiple long-running I/O operations.
  * **Secure and Flexible Configuration**: Implementing a professional, layered configuration system with Viper and GoDotEnv that decouples the application from its environment and handles secrets securely.
  * **Modular and Testable Design**: Encapsulating discrete functionalities—Git interaction, API clients, and TUI logic—into separate modules, leading to cleaner and more maintainable code.
  * **AI-Powered Automation**: Utilizing an LLM not just as a novelty, but as a practical tool to automate the creative and often tedious task of writing high-quality documentation.

This project serves as a strong foundation that can be extended with even more powerful features. Potential future enhancements include:

  * **Interactive Content Editing**: Incorporate a `textarea` component from the `bubbles` library to allow the user to review and edit the AI-generated title and description directly within the TUI before submission.[15]
  * **First-Run Configuration Wizard**: Build a separate Bubble Tea model that runs on the tool's first execution, guiding the user through setting up their API keys, default project, and other preferences.
  * **Multi-Platform Support**: Extend the tool's capabilities by implementing new API clients for other services like GitLab, Bitbucket, or alternative project management platforms such as Linear or Asana.
  * **Git Hook Integration**: For an even more seamless experience, the tool could be integrated as a `pre-push` git hook, automatically launching the PR and ticket creation process whenever new commits are pushed to a remote repository.

<!-- end list -->

```
```

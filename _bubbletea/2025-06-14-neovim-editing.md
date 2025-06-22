---
layout: post
title: neovim within bubble
categories: [go, bubbletea, neovim]
tags: [bubbletea, go, neovim]
---
## The Neovim-in-TUI Symbiosis: Seamlessly Editing Text in Go with Bubble Tea

Terminal User Interfaces (TUIs) built in Go are powerful, fast, and portable. Frameworks like [Bubble Tea](https://github.com/charmbracelet/bubbletea) have made creating them more accessible than ever. However, one common challenge is rich text input. While components like the `textarea` from the [Bubbles](https://github.com/charmbracelet/bubbles) library are excellent for simple, multi-line input, they can't compete with the power and familiarity of a dedicated terminal editor like Neovim.

What if you didn't have to choose?

This article will guide you through a powerful pattern: launching Neovim from within your Bubble Tea application to edit content. We'll build a sample app where a user can edit a block of text (like a Jira issue description). When the user triggers an "edit" command, we will:

1.  Open the current text in a full-screen Neovim session.
2.  Allow the user to edit the text using all of Neovim's features.
3.  When the user saves and quits Neovim, capture the new content back in the Go application.
4.  Seamlessly return to the Bubble Tea interface, now updated with the edited text.

### The Core Components

To achieve this, we rely on a few key pieces of Go's standard library and the Charm bracelet ecosystem.

1.  **Bubble Tea (`tea`):** The engine of our application. It's an event-driven framework based on the Elm Architecture (`Model`, `Update`, `View`), which manages our application's state and renders the UI.
2.  **Bubbles (`textarea`):** We'll use the `textarea` component to display our text. While we could use a simple string, `textarea` provides nice features like viewport management for text that's too long to display at once.
3.  **The `os/exec` Package:** This is the workhorse from the Go standard library. It allows us to run external commands—in our case, `nvim`. The key is to configure it correctly so it takes over the terminal for the editing session.

### How the "Flip" from TUI to Neovim Works

The magic of this process lies in how programs interact with the terminal.

1.  **Bubble Tea Takes Control:** When you run a `tea.Program`, it puts the terminal into a special "raw mode." This allows it to capture every keystroke and control every character printed to the screen, which is how it can draw an interactive UI.

2.  **Pausing the Program:** We will design our application to launch Neovim as a blocking command. While our Go program waits for the `nvim` process to complete, the Bubble Tea event loop is effectively paused.

3.  **Handing Off the Terminal:** We will configure the `exec.Command` for Neovim to use the current terminal's standard input, output, and error streams (`os.Stdin`, `os.Stdout`, `os.Stderr`). When the `nvim` command runs, it's a TUI application itself and knows how to take full control of the terminal, drawing its own interface. To the user, it looks like your app has been replaced by Neovim.

4.  **The Return Journey:** When the user saves and quits Neovim (e.g., with `:wq`), the `nvim` process terminates. This unblocks our Go program. The `tea.Program` automatically resumes control of the terminal, puts it back into raw mode, and re-renders its own UI based on the application's current state.

By passing the text back and forth via a temporary file, we complete the data round-trip.

### Putting It All Together: The Code Example

Let's build a complete, runnable example. Our application will display a text area with a mock Jira description. Pressing `e` will open this text in Neovim.

First, ensure you have the necessary libraries:

```bash
go get github.com/charmbracelet/bubbletea
go get github.com/charmbracelet/bubbles
```

Now, here is the complete `main.go`:

```go
// main.go
package main

import (
  "fmt"
  "io/ioutil"
  "os"
  "os/exec"
  "strings"

  "github.com/charmbracelet/bubbles/textarea"
  "github.com/charmbracelet/bubbles/viewport"
  tea "github.com/charmbracelet/bubbletea"
  "github.com/charmbracelet/lipgloss"
)

// --- Model ---

type model struct {
  textarea   textarea.Model
  viewport   viewport.Model
  isEditing  bool
  err        error
}

const (
  // The editor to use. You can make this configurable.
  editor = "nvim"
)

var (
  titleStyle = lipgloss.NewStyle().Background(lipgloss.Color("62")).Foreground(lipgloss.Color("230")).Padding(0, 1)
  helpStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
)

// Define a custom message to signal that the editor has finished.
type editorFinishedMsg struct {
  err  error
  file string // The temporary file path
}

func initialModel() model {
  ta := textarea.New()
  ta.Placeholder = "This is a mock Jira description. Press 'e' to edit it in Neovim."
  ta.SetValue(`## Project Phoenix

	### Overview
	This project aims to refactor the legacy billing system.

	### Key Deliverables
	- [ ] Migrate database to Postgres
	- [ ] Implement new REST API endpoints
	- [ ] Deprecate the old SOAP service`)
  ta.Focus()

  // The textarea is our "write" model, but for the main view,
  // we'll use a viewport to display the content, as it gives
  // us more control over the presentation.
  vp := viewport.New(100, 15) // Width and height will be updated on window size messages
  vp.SetContent(ta.View())

  return model{
	textarea:  ta,
	viewport:  vp,
	isEditing: false,
	err:       nil,
  }
}

// --- Bubble Tea Methods ---

func (m model) Init() tea.Cmd {
  return textarea.Blink
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
  var cmds []tea.Cmd
  var cmd tea.Cmd

  switch msg := msg.(type) {
  case tea.KeyMsg:
	switch msg.Type {
	case tea.KeyCtrlC, tea.KeyEsc:
	  return m, tea.Quit
	case tea.KeyRunes:
	  // If we're not editing, check for the 'e' key to start editing.
	  if !m.isEditing && string(msg.Runes) == "e" {
		m.isEditing = true
		// This is where we trigger the external editor.
		// We return a command that will execute the editor.
		return m, openEditor(m.textarea.Value())
	  }
	}

  case tea.WindowSizeMsg:
	// Update the viewport size on window resize.
	m.viewport.Width = msg.Width
	m.viewport.Height = msg.Height - lipgloss.Height(m.headerView()) - lipgloss.Height(m.footerView())
	// Also update the textarea view since it's used to set the viewport content.
	m.textarea.SetWidth(msg.Width)
	m.viewport.SetContent(m.textarea.View())

  // This is the custom message we defined. It's sent when the editor exits.
  case editorFinishedMsg:
	m.isEditing = false
	if msg.err != nil {
	  m.err = msg.err
	  return m, tea.Quit
	}
	// Read the content from the temporary file.
	content, err := ioutil.ReadFile(msg.file)
	if err != nil {
	  m.err = err
	  return m, tea.Quit
	}
	// Update the textarea with the new content.
	m.textarea.SetValue(string(content))
	m.viewport.SetContent(m.textarea.View())

  case error:
	m.err = msg
	return m, nil
  }

  // Pass messages to the viewport and textarea.
  m.viewport, cmd = m.viewport.Update(msg)
  cmds = append(cmds, cmd)
  m.textarea, cmd = m.textarea.Update(msg)
  cmds = append(cmds, cmd)

  return m, tea.Batch(cmds...)
}

func (m model) View() string {
  if m.err != nil {
	return fmt.Sprintf("An error occurred: %v", m.err)
  }

  // If we are in the middle of an edit, show a waiting message.
  if m.isEditing {
	return "Editing content in Neovim... (save and quit to return)"
  }

  return fmt.Sprintf(
	"%s\n%s\n%s",
	m.headerView(),
	m.viewport.View(),
	m.footerView(),
	)
}

func (m model) headerView() string {
  return titleStyle.Render("Jira Description Editor")
}

func (m model) footerView() string {
  return helpStyle.Render(strings.Repeat(" ", 2) + "↑/↓: navigate | e: edit | ctrl+c: quit")
}

// --- External Editor Logic ---

// openEditor is a tea.Cmd that launches the editor.
func openEditor(content string) tea.Cmd {
  return func() tea.Msg {
	// Create a temporary file to store the content.
	// The "*" in the pattern means a random string will be added.
	tmpfile, err := ioutil.TempFile("", "*.md")
	if err != nil {
	  return editorFinishedMsg{err: fmt.Errorf("could not create temp file: %w", err)}
	}
	defer os.Remove(tmpfile.Name()) // Clean up the file afterwards.

	// Write the current content to the temp file.
	_, err = tmpfile.Write([]byte(content))
	if err != nil {
	  return editorFinishedMsg{err: fmt.Errorf("could not write to temp file: %w", err)}
	}
	if err := tmpfile.Close(); err != nil {
	  return editorFinishedMsg{err: fmt.Errorf("could not close temp file: %w", err)}
	}

	// --- The Core of the "Flip" ---
	cmd := exec.Command(editor, tmpfile.Name())
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	// This will block until the editor is closed.
	if err = cmd.Run(); err != nil {
	  return editorFinishedMsg{err: fmt.Errorf("error running editor: %w", err)}
	}

	// When the editor exits, send a message back to the Bubble Tea
	// update loop with the path to the modified file.
	return editorFinishedMsg{file: tmpfile.Name()}
  }
}

// --- Main Function ---

func main() {
  p := tea.NewProgram(
	initialModel(),
	tea.WithAltScreen(),       // Use the alternative screen buffer
	tea.WithMouseCellMotion(), // Enable mouse events
	)

  if err := p.Start(); err != nil {
	fmt.Printf("Alas, there's been an error: %v", err)
	os.Exit(1)
  }
}
```

### Dissecting the Key Logic

1.  **The `openEditor` Command (`tea.Cmd`)**:
This is not just a function; it returns a `tea.Cmd`. In Bubble Tea, commands are functions that perform I/O (like network requests or, in this case, file system access and process execution) and return a `tea.Msg` when they are done. This is how Bubble Tea keeps the `Update` loop from blocking.

2.  **The Temporary File**:
The `ioutil.TempFile` function is the perfect tool for this job. It safely creates a unique file that we can write our initial content to. We then pass this file's name to Neovim. Crucially, we `defer os.Remove()` to ensure the file gets cleaned up even if errors occur.

3.  **The `editorFinishedMsg`**:
This custom message is the bridge back to our application. When `openEditor` finishes its work, it doesn't modify the model directly. Instead, it sends an `editorFinishedMsg` containing the path of the edited file. The `Update` function has a `case` to handle this specific message, at which point it safely reads the file and updates the model's state. This respects the event-driven architecture and avoids race conditions.

4.  **`tea.WithAltScreen()`**:
In the `main` function, we initialize our program with this option. It tells Bubble Tea to use the terminal's alternative screen buffer, which is a common practice for TUI applications. It ensures that when your app exits, the user's original terminal screen and scrollback history are restored, leaving no trace. This enhances the seamless feel of the integration.

### Conclusion

This pattern of "shelling out" to a powerful, dedicated tool like Neovim is a form of software composition at the user-interface level. You get the best of both worlds: a lightweight, purpose-built TUI in Go for managing state and workflow, and a feature-rich, user-configurable editor for the complex task of text manipulation. By understanding how to manage the terminal session and pass data through the file system, you can create surprisingly powerful and ergonomic TUI applications.

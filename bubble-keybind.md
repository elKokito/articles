## Declarative Keybindings in Bubble Tea: A Guide to the `bubbles/key` Package

Building a rich, interactive terminal user interface (TUI) with Bubble Tea is a rewarding experience. As your application grows beyond simple views, you'll inevitably need to handle user input in a structured, maintainable way. While you can handle `tea.KeyMsg` events directly with a `switch` statement, this can become cumbersome, especially when dealing with multiple components, context-sensitive actions, and help menus.

This is where the `bubbles/key` package shines. It provides a declarative way to define keybindings, decouple them from your update logic, and automatically generate help views. This 20-minute guide will walk you through the architecture of the `key` package, how it integrates with the Bubble Tea model, and how to use it effectively with various Bubbles components.

### The Architecture: What is a `key.Binding`?

At the heart of the system is the `key.Binding` struct. Instead of thinking about raw key presses like `"ctrl+c"` or `"k"`, you think in terms of *actions*. A `key.Binding` represents a single user action and contains two key pieces of information:

1.  **The Keys:** The actual keyboard inputs that trigger the action (e.g., `up`, `k`).
2.  **The Help Text:** A description of the action used for generating help views (e.g., "move up").

Let's look at the definition from the source file `key/key.go`:

```go
// key/key.go

// Binding describes a set of keybindings and, optionally, their associated
// help text.
type Binding struct {
	keys     []string
	help     Help
	disabled bool
}

// Help is help information for a given keybinding.
type Help struct {
	Key  string
	Desc string
}
```

You create a binding using `key.NewBinding` with functional options:

* `key.WithKeys(keys ...string)`: Assigns one or more keys to the binding.
* `key.WithHelp(key string, desc string)`: Assigns the help text. The `key` is what's shown for the binding (e.g., "↑/k"), and the `desc` is the description (e.g., "move up").

A common pattern is to group related bindings into a `KeyMap` struct. This keeps your bindings organized and easy to manage.

```go
// A KeyMap for a simple counter application
type keyMap struct {
	Up   key.Binding
	Down key.Binding
	Quit key.Binding
}

var defaultKeyMap = keyMap{
	Up: key.NewBinding(
		key.WithKeys("k", "up"),
		key.WithHelp("↑/k", "increment"),
	),
	Down: key.NewBinding(
		key.WithKeys("j", "down"),
		key.WithHelp("↓/j", "decrement"),
	),
	Quit: key.NewBinding(
		key.WithKeys("q", "ctrl+c"),
		key.WithHelp("q", "quit"),
	),
}
```

This `keyMap` struct now declaratively represents the actions a user can take, completely separate from the application logic.

### Integration with the Bubble Tea Update Loop

So, how do you connect these bindings to your application's `Update` function? The bridge is the `key.Matches` function.

When your Bubble Tea model receives a `tea.KeyMsg`, you pass that message and a `key.Binding` to `key.Matches`. It returns `true` if the key press matches one of the keys defined in the binding.

This leads to a very clean and readable `Update` function:

```go
// main.go

import (
	"fmt"
	"os"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
)

type model struct {
	count  int
	keymap keyMap
}

// ... (keyMap struct from above) ...

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, m.keymap.Up):
			m.count++
		case key.Matches(msg, m.keymap.Down):
			m.count--
		case key.Matches(msg, m.keymap.Quit):
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() string {
	return fmt.Sprintf("Count: %d\n\nPress 'q' to quit.", m.count)
}

func main() {
	m := model{keymap: defaultKeyMap}
	if _, err := tea.NewProgram(m).Run(); err != nil {
		fmt.Println("Error running program:", err)
		os.Exit(1)
	}
}
```

This pattern is fundamental. Instead of `case "k":` or `case "up":`, you check `case key.Matches(msg, m.keymap.Up):`. This decouples the specific key from the action itself. If you want to change the key for "increment" to `"i"`, you only have to change it in one place—your `keyMap` definition—and the `Update` logic remains untouched.

### Using Keymaps with Bubbles Components

The real power of this pattern becomes evident when you use pre-built Bubbles components like `list`, `table`, or `viewport`. These components come with their own `KeyMap` that defines their default behavior.

Let's take the `list` component as an example. When you create a `list.Model`, it's initialized with a `list.DefaultKeyMap()`. This keymap, found in `list/keys.go`, defines bindings for all standard list operations: moving the cursor, pagination, filtering, and more.

```go
// list/keys.go (simplified)
func DefaultKeyMap() KeyMap {
	return KeyMap{
		CursorUp: key.NewBinding(
			key.WithKeys("up", "k"),
			key.WithHelp("↑/k", "up"),
		),
		CursorDown: key.NewBinding(
			key.WithKeys("down", "j"),
			key.WithHelp("↓/j", "down"),
		),
		Filter: key.NewBinding(
			key.WithKeys("/"),
			key.WithHelp("/", "filter"),
		),
		// ... and many more
	}
}
```

The `list.Model`'s own `Update` function uses this internal keymap with `key.Matches` to handle its state. This is a crucial concept: **the component manages its own keybindings**. You, as the developer using the list, don't need to write the logic for moving the cursor up or down. You just pass the `tea.Msg` to the list's `Update` method, and it handles the rest.

```go
// An example model that uses a list
type mainModel struct {
	list list.Model
}

func (m mainModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		// If the list is filtering, it needs to handle keys exclusively
		if m.list.FilterState() == list.Filtering {
			var cmd tea.Cmd
			m.list, cmd = m.list.Update(msg)
			return m, cmd
		}

		// Handle global quit key.
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}
	}

	// All other messages are passed to the list's Update function.
	// The list will use its internal KeyMap to handle navigation, etc.
	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}
```

You can also *customize* a component's keymap. For example, if you wanted to change the filter key from `/` to `f`:

```go
myList := list.New(...)
myList.KeyMap.Filter = key.NewBinding(
    key.WithKeys("f"),
    key.WithHelp("f", "filter"),
)
```

### Dynamic Keybindings and Automatic Help

This architecture solves organization and abstraction, but its killer feature is how it handles dynamic states and help generation.

#### Enabling and Disabling Bindings

Often, a keybinding should only be active in a certain context. For example, the `list` component's "clear filter" key (`esc`) should only work when a filter is actually applied. The `key.Binding` has a `SetEnabled(bool)` method for this.

The `list` component manages this for you automatically. When you start filtering, it disables navigation keys and enables the "accept" and "cancel" filter keys. When you apply the filter, it re-enables navigation and enables the "clear filter" key.

`key.Matches` will only return `true` for bindings that are enabled. This makes your `Update` logic even cleaner, as you don't need to add extra `if` conditions to check the application's state.

#### The `help` Component

Because each `key.Binding` contains its own help text, we can automatically generate a help view. The `bubbles/help` component is designed to do exactly this.

To use it, your `KeyMap` struct must satisfy the `help.KeyMap` interface by implementing two methods:
* `ShortHelp() []key.Binding`
* `FullHelp() [][]key.Binding`

These methods return the bindings that should be displayed in the compact and expanded help views, respectively.

```go
// Make our keyMap from before satisfy the help.KeyMap interface
func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Up, k.Down, k.Quit}
}

func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down}, // First column
		{k.Quit},       // Second column
	}
}

// A model that now includes a help view
type model struct {
	count  int
	keymap keyMap
	help   help.Model
}

func NewModel() model {
	return model{
		keymap: defaultKeyMap,
		help:   help.New(),
	}
}

// In your View function:
func (m model) View() string {
	countView := fmt.Sprintf("Count: %d\n\n", m.count)
	helpView := m.help.View(m.keymap) // Pass the keymap to the help view
	return countView + helpView
}
```

The `help.View()` method will iterate through the bindings you provide and render them. Crucially, **it will automatically hide any bindings that are disabled**. This is incredibly powerful. When the `list` component disables the "filter" key, it automatically disappears from the help view, and the "accept filter" key appears. You get context-aware help for free.

### Putting it all Together

Here is a final, more complete example that uses a `list` and a `help` view, demonstrating how the components work together seamlessly.

```go
package main

import (
	"fmt"
	"os"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	docStyle = lipgloss.NewStyle().Margin(1, 2)
)

// Define a keymap for our main application
type mainKeyMap struct {
	Quit key.Binding
	Help key.Binding
}

func (k mainKeyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Help, k.Quit}
}

func (k mainKeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Help, k.Quit},
	}
}

var mainKeys = mainKeyMap{
	Quit: key.NewBinding(
		key.WithKeys("q", "ctrl+c"),
		key.WithHelp("q", "quit"),
	),
	Help: key.NewBinding(
		key.WithKeys("?"),
		key.WithHelp("?", "toggle help"),
	),
}

type model struct {
	list list.Model
	keys mainKeyMap
	help help.Model
}

func newModel() model {
	items := []list.Item{
		list.Item("Raspberry"),
		list.Item("Blueberry"),
		list.Item("Strawberry"),
	}

	// The list component will use its default keymap for navigation.
	l := list.New(items, list.NewDefaultDelegate(), 0, 0)
	l.Title = "What's your favorite berry?"

	return model{
		list: l,
		keys: mainKeys,
		help: help.New(),
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		h, v := docStyle.GetFrameSize()
		m.list.SetSize(msg.Width-h, msg.Height-v)
		m.help.Width = msg.Width

	case tea.KeyMsg:
		// Don't let the list handle our keybindings.
		switch {
		case key.Matches(msg, m.keys.Quit):
			return m, tea.Quit
		case key.Matches(msg, m.keys.Help):
			m.help.ShowAll = !m.help.ShowAll
		}
	}

	// Pass the message to the list's update function.
	// It will handle its own keybindings (up, down, filter, etc.).
	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m model) View() string {
	// We need to merge our main keymap with the list's keymap for the help view.
	// The help component will automatically handle showing/hiding keys
	// based on the list's state.
	m.list.KeyMap.ShowFullHelp = m.keys.Help
	m.list.KeyMap.CloseFullHelp = m.keys.Help

	helpView := m.help.View(m.list) // The list is a help.KeyMap!
	listView := docStyle.Render(m.list.View())

	return listView + "\n" + helpView
}

func main() {
	if _, err := tea.NewProgram(newModel()).Run(); err != nil {
		fmt.Println("Error running program:", err)
		os.Exit(1)
	}
}

```

### Conclusion

The `bubbles/key` package provides a robust and elegant solution for managing keyboard input in Bubble Tea applications. By thinking in terms of actions and bindings rather than raw key presses, you create code that is:

* **Declarative:** Keymaps are easy to read and understand.
* **Decoupled:** Your `Update` logic is cleaner and not tied to specific keys.
* **Maintainable:** Changing a keybinding is a one-line change in the `KeyMap` definition.
* **Self-Documenting:** The same `KeyMap` that drives your logic also generates your help views, ensuring they are always in sync.

As you build more complex TUIs, embracing this architecture will save you significant time and effort, allowing you to focus on creating a great user experience.

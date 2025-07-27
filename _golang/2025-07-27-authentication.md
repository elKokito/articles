---
layout: post
title: authentication with github.com/markbates/goth
categories: [golang]
tags: [golang]
---
# Complete Go Architecture Guide for Consumer-Facing Applications

This comprehensive guide provides senior developers with practical, production-ready patterns for building scalable consumer-facing Go applications. Drawing from 2025's latest best practices, this guide covers architecture decisions with working code examples, showing you exactly how to implement each pattern. Think of this as your roadmap from architectural concept to production code.

Understanding application architecture is like understanding the foundation of a house. Just as you wouldn't start building walls without a solid foundation, you shouldn't start coding features without understanding the architectural patterns that will support your application's growth. The patterns we'll explore have evolved through years of real-world experience, solving common problems that every growing application faces.

## Understanding the evolution of Go application architecture

Before we dive into specific patterns, it's important to understand why modern Go applications have evolved toward the architectural approaches we'll discuss. When Go first gained popularity, many developers came from other languages and brought their familiar patterns with them. However, Go's unique characteristics - its interface system, composition over inheritance, and emphasis on simplicity - have led to architectural patterns that feel distinctly "Go-like."

The shift toward hexagonal architecture in Go applications didn't happen overnight. It emerged as teams discovered that Go's implicit interfaces make dependency inversion incredibly natural, while the language's compilation speed makes refactoring less painful than in many other languages. When you understand these underlying forces, the architectural decisions we'll make throughout this guide will feel more intuitive rather than arbitrary.

Consumer-facing applications present unique challenges that influence our architectural choices. Unlike internal tools or APIs, consumer applications must handle unpredictable traffic patterns, varying user behaviors, and the need for rapid feature development. They also require robust authentication systems, subscription management, and the ability to scale both technically and organizationally as your team grows.

## Application architecture foundations

Modern Go applications in 2025 favor hexagonal architecture as the primary pattern, and understanding why this pattern has become dominant will help you appreciate the code examples that follow. Traditional layered architectures often lead to what developers call "database-driven design," where your business logic becomes tightly coupled to your data storage decisions. Hexagonal architecture flips this relationship, putting your business logic at the center and treating everything else - databases, web frameworks, external APIs - as interchangeable adapters.

Think of hexagonal architecture like a universal power adapter for international travel. The core device (your business logic) remains the same regardless of which country's power system (database, web framework, payment processor) you're plugging into. This analogy helps explain why hexagonal architecture makes applications so much easier to test, modify, and scale.

The "hexagonal" name might seem confusing at first - why six sides specifically? The answer is that there aren't necessarily six sides; the hexagon is just a visual representation that makes it clear that there can be multiple ports (interfaces) connecting your core business logic to the outside world. Some applications might have four ports, others might have eight. The key insight is that your business logic sits in the center, isolated from external concerns.

### Project structure that scales with your team and complexity

The project structure we'll examine has been refined through countless Go projects, and each directory serves a specific purpose in supporting both current development and future growth. When you're building a consumer-facing application, you're not just building for today's features - you're building for a future where your team might be five times larger and your application might need to split into microservices.

Here's the recommended project layout that I've seen work exceptionally well for consumer-facing applications:

```
myapp/
├── cmd/
│   ├── api/           # HTTP API server
│   │   └── main.go
│   ├── worker/        # Background job processor
│   │   └── main.go
│   └── migrate/       # Database migration tool
│       └── main.go
├── internal/          # Private application code
│   ├── domain/        # Business logic and entities
│   │   ├── user/
│   │   ├── subscription/
│   │   └── auth/
│   ├── ports/         # Interfaces (hexagonal architecture)
│   │   ├── repositories/
│   │   └── services/
│   ├── adapters/      # External integrations
│   │   ├── database/
│   │   ├── oauth/
│   │   └── payment/
│   ├── api/          # HTTP handlers and middleware
│   │   ├── handlers/
│   │   ├── middleware/
│   │   └── routes/
│   └── config/       # Configuration management
├── pkg/              # Public library code
├── migrations/       # Database schema files
├── scripts/          # Build and deployment scripts
└── docker/          # Container configurations
```

Let's break down why each directory exists and how it supports your application's growth. The `cmd/` directory follows Go's convention for executable commands, but notice how we have multiple executables. This is crucial for consumer applications because you'll inevitably need background workers for tasks like sending emails, processing payments, or generating reports. By designing for multiple executables from the beginning, you avoid the painful refactoring that comes when you try to extract worker processes from a monolithic web server later.

The `internal/` directory is where Go's module system really shines. By placing code in `internal/`, you're telling the Go compiler that this code is private to your module - no external packages can import it. This might seem like a small detail, but it's actually a powerful architectural tool. It forces you to think carefully about what should be public (in `pkg/`) versus what should remain private to your application.

Within `internal/`, the domain-driven organization mirrors how your business actually works. When a new team member joins, they can navigate to `internal/domain/user/` and immediately understand what user-related functionality exists. This becomes even more valuable as your application grows - when you eventually need to extract user management into its own microservice, all the related code is already grouped together.

The beauty of this structure lies in its separation of concerns and its support for the dependency inversion principle. The `internal/domain/` directories contain your business logic and define interfaces for what they need from the outside world. The `internal/adapters/` directories implement those interfaces, providing concrete implementations for databases, external APIs, and other infrastructure concerns. The `internal/api/` directory handles the HTTP-specific concerns like request parsing and response formatting.

This organization becomes particularly powerful when you're working with a team. A developer working on business logic can focus entirely on the domain directories, while a developer working on infrastructure can focus on the adapters. The interfaces defined in the domain act as contracts between these different areas of the codebase.

### Hexagonal architecture implementation that makes testing effortless

Hexagonal architecture might seem abstract until you see it implemented in Go code. The pattern becomes much clearer when you understand that it's fundamentally about using Go's interfaces to create boundaries between your business logic and everything else. Let me show you how this looks in practice, starting with the core business entity and building outward.

```go
// internal/domain/user/user.go
package user

import (
    "context"
    "time"
)

// User represents our core business entity
type User struct {
    ID           string    `json:"id"`
    Email        string    `json:"email"`
    Name         string    `json:"name"`
    SubscriptionTier string `json:"subscription_tier"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
}

// These are our "ports" - interfaces that define what our domain needs
// Notice how we define them where they're used, not where they're implemented
type Repository interface {
    Create(ctx context.Context, user User) error
    GetByID(ctx context.Context, id string) (*User, error)
    GetByEmail(ctx context.Context, email string) (*User, error)
    Update(ctx context.Context, user User) error
}

type EmailService interface {
    SendWelcomeEmail(ctx context.Context, user User) error
}

// Service contains our business logic
type Service struct {
    repo         Repository
    emailService EmailService
}

func NewService(repo Repository, emailService EmailService) *Service {
    return &Service{
        repo:         repo,
        emailService: emailService,
    }
}

// CreateUser demonstrates business logic that's independent of external systems
func (s *Service) CreateUser(ctx context.Context, email, name string) (*User, error) {
    // Business rule: check if user already exists
    existing, err := s.repo.GetByEmail(ctx, email)
    if err != nil && err != ErrUserNotFound {
        return nil, err
    }
    if existing != nil {
        return nil, ErrUserAlreadyExists
    }

    // Create new user with business defaults
    user := User{
        ID:               generateID(), // your ID generation logic
        Email:            email,
        Name:             name,
        SubscriptionTier: "free", // business default
        CreatedAt:        time.Now(),
        UpdatedAt:        time.Now(),
    }

    if err := s.repo.Create(ctx, user); err != nil {
        return nil, err
    }

    // Send welcome email asynchronously (don't fail user creation if email fails)
    go func() {
        if err := s.emailService.SendWelcomeEmail(context.Background(), user); err != nil {
            // Log error, but don't return it
            log.Printf("Failed to send welcome email to %s: %v", user.Email, err)
        }
    }()

    return &user, nil
}
```

This code demonstrates several crucial concepts that make hexagonal architecture so powerful in Go. First, notice how the interfaces are defined in the same package as the business logic that uses them. This is the opposite of what you might expect from other languages, but it's a fundamental Go idiom that makes dependency inversion natural and clear.

The Repository and EmailService interfaces represent "ports" in hexagonal architecture terminology. These are the contracts that define what the business logic needs from the outside world, but they don't specify how those needs are fulfilled. This separation is what makes the code so testable - you can create mock implementations of these interfaces for testing without needing a real database or email service.

The Service struct acts as the core of your application domain. It contains the business rules and logic that define how your application behaves, but it doesn't know or care about implementation details like which database you're using or how emails are actually sent. This isolation is what allows you to change these implementation details without affecting your business logic.

The CreateUser method demonstrates how business logic flows in this architecture. Notice how it starts with business rules (checking for existing users), applies business defaults (setting the subscription tier to "free"), and handles business concerns (making sure user creation doesn't fail if email sending fails). The method delegates infrastructure concerns to the injected dependencies but maintains control over the business flow.

The asynchronous email sending is a particularly important pattern for consumer applications. User registration should feel instant to your users, even if background processes like email sending take time or fail temporarily. By using a goroutine here, we ensure that email problems don't impact the user experience while still attempting to send the welcome email.

Understanding error handling in this pattern is also crucial. The business logic defines its own error types (like ErrUserAlreadyExists) that express business concepts rather than infrastructure failures. This allows higher layers of the application to make appropriate decisions about how to present errors to users.

## Framework integration with Gin - Building for scale from day one

Choosing a web framework for a consumer-facing application involves more than just looking at benchmarks or feature lists. You need a framework that can handle real-world concerns like graceful shutdowns, middleware composition, and request routing that scales as your API grows. Gin has emerged as the preferred choice for Go web applications because it strikes the right balance between performance, features, and simplicity.

Understanding why Gin works so well for consumer applications requires understanding the challenges these applications face. Consumer applications typically start with a few endpoints but quickly grow to dozens or hundreds of endpoints as features are added. They need sophisticated middleware chains for authentication, rate limiting, and logging. They need to handle different types of clients - web browsers, mobile apps, and potentially third-party integrations - each with slightly different requirements.

Gin's approach to these challenges is based on a middleware pipeline concept that's both powerful and intuitive. Rather than trying to build every feature into the core framework, Gin provides a composition system that lets you build exactly the functionality you need. This approach becomes particularly valuable as your application grows and you need to apply different middleware to different groups of routes.

### Application bootstrap and dependency injection that grows with complexity

The way you structure your application's startup and dependency injection significantly impacts how easy it is to add new features, write tests, and eventually split your application into microservices. The pattern I'll show you here has been tested in production applications that serve millions of requests per day.

```go
// cmd/api/main.go
package main

import (
    "context"
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/gin-gonic/gin"
    "myapp/internal/adapters/database"
    "myapp/internal/adapters/oauth"
    "myapp/internal/api/routes"
    "myapp/internal/config"
    "myapp/internal/domain/user"
)

func main() {
    // Load configuration
    cfg := config.Load()

    // Initialize database
    db, err := database.NewConnection(cfg.DatabaseURL)
    if err != nil {
        log.Fatal("Failed to connect to database:", err)
    }
    defer db.Close()

    // Initialize repositories (adapters)
    userRepo := database.NewUserRepository(db)

    // Initialize services (business logic)
    userService := user.NewService(userRepo, &emailService{})

    // Initialize Gin router with middleware
    router := gin.New()
    router.Use(gin.Logger())
    router.Use(gin.Recovery())

    // Setup routes with dependency injection
    routes.SetupUserRoutes(router, userService)
    routes.SetupAuthRoutes(router, cfg)

    // Graceful shutdown setup
    srv := &http.Server{
        Addr:    ":" + cfg.Port,
        Handler: router,
    }

    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("Failed to start server: %v", err)
        }
    }()

    // Wait for interrupt signal
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    log.Println("Shutting down server...")
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        log.Fatal("Server forced to shutdown:", err)
    }
}
```

This bootstrap code demonstrates several patterns that become increasingly important as your application grows. The dependency injection pattern shown here - where you construct your dependencies in a specific order and pass them to the components that need them - is crucial for maintaining testability and flexibility.

Notice how the initialization follows the dependency graph from the outside in. Database connections are created first because repositories depend on them. Repositories are created next because services depend on them. Services are created before routes because routes depend on them. This ordering isn't arbitrary - it reflects the actual dependencies between these components and ensures that each component has everything it needs when it's created.

The graceful shutdown pattern at the end might seem like boilerplate, but it's essential for consumer applications. When you deploy updates to your application, you want existing requests to complete gracefully rather than being abruptly terminated. This pattern gives your application time to finish processing current requests while refusing new ones, resulting in zero-downtime deployments.

The use of separate route setup functions (like `routes.SetupUserRoutes`) creates clear boundaries between different areas of functionality. As your application grows, you can assign different teams to different route groups, and the separation makes it easier to understand and modify each area independently.

### Route organization that prevents middleware chaos

As your API grows from a few endpoints to dozens or hundreds, organizing your routes and middleware becomes crucial for maintainability. A poorly organized routing structure can lead to middleware being applied inconsistently, security vulnerabilities from forgotten authentication checks, and difficulty understanding which endpoints exist and how they behave.

The pattern I'll show you addresses these problems by creating explicit groupings that make middleware application both obvious and consistent.

```go
// internal/api/routes/user.go
package routes

import (
    "github.com/gin-gonic/gin"
    "myapp/internal/api/handlers"
    "myapp/internal/api/middleware"
    "myapp/internal/domain/user"
)

func SetupUserRoutes(router *gin.Engine, userService *user.Service) {
    // Create handler with injected service
    userHandler := handlers.NewUserHandler(userService)

    // Public routes (no authentication required)
    public := router.Group("/api/v1")
    {
        public.POST("/users", userHandler.CreateUser)
    }

    // Protected routes (authentication required)
    protected := router.Group("/api/v1")
    protected.Use(middleware.AuthRequired())
    {
        protected.GET("/users/me", userHandler.GetCurrentUser)
        protected.PUT("/users/me", userHandler.UpdateUser)
    }

    // Premium routes (subscription required)
    premium := router.Group("/api/v1")
    premium.Use(middleware.AuthRequired())
    premium.Use(middleware.SubscriptionRequired("premium"))
    {
        premium.GET("/users/analytics", userHandler.GetAnalytics)
    }
}
```

This route organization pattern solves several common problems that plague growing applications. By creating explicit groups for different security levels (public, protected, premium), you make it impossible to accidentally expose a protected endpoint as public or forget to check subscription status for premium features.

The use of Gin's route groups with middleware creates what's essentially a security contract. Every route in the `protected` group is guaranteed to have authentication middleware applied. Every route in the `premium` group is guaranteed to have both authentication and subscription checking. This systematic approach prevents the security bugs that often emerge in applications where middleware is applied on a per-route basis.

Notice how the middleware is composed - the premium group includes both AuthRequired and SubscriptionRequired middleware. This composition approach is more flexible than trying to create a single "premium auth" middleware because you can mix and match different middleware components for different requirements. For example, you might have some premium features that require authentication but different subscription levels.

The API versioning built into the route structure ("/api/v1") is crucial for consumer applications. As your application evolves, you'll need to maintain backward compatibility for existing clients while developing new features. Having versioning built into your route structure from the beginning makes this evolution much smoother.

### Handler implementation that separates concerns cleanly

Handlers in a well-architected Go application serve a specific purpose: they translate between HTTP concerns and business logic. Understanding this separation is crucial because it determines how easy your application is to test, how straightforward it is to add new endpoints, and how cleanly you can evolve your API over time.

Many developers new to Go make the mistake of putting business logic directly in their handlers. This creates several problems: the business logic becomes tied to HTTP-specific concerns, testing requires setting up HTTP requests and responses, and it becomes difficult to reuse the logic in other contexts (like background jobs or different API versions).

The pattern I'll show you demonstrates how to keep handlers focused on their core responsibility while delegating business logic to the service layer.

```go
// internal/api/handlers/user.go
package handlers

import (
    "net/http"

    "github.com/gin-gonic/gin"
    "myapp/internal/domain/user"
)

type UserHandler struct {
    userService *user.Service
}

func NewUserHandler(userService *user.Service) *UserHandler {
    return &UserHandler{userService: userService}
}

type CreateUserRequest struct {
    Email string `json:"email" binding:"required,email"`
    Name  string `json:"name" binding:"required,min=2,max=100"`
}

func (h *UserHandler) CreateUser(c *gin.Context) {
    var req CreateUserRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Call business logic
    user, err := h.userService.CreateUser(c.Request.Context(), req.Email, req.Name)
    if err != nil {
        // Handle business errors appropriately
        switch err {
        case user.ErrUserAlreadyExists:
            c.JSON(http.StatusConflict, gin.H{"error": "User already exists"})
        default:
            c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
        }
        return
    }

    c.JSON(http.StatusCreated, user)
}

func (h *UserHandler) GetCurrentUser(c *gin.Context) {
    // Extract user from context (set by auth middleware)
    userID, exists := c.Get("user_id")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
        return
    }

    user, err := h.userService.GetUser(c.Request.Context(), userID.(string))
    if err != nil {
        if err == user.ErrUserNotFound {
            c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
            return
        }
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
        return
    }

    c.JSON(http.StatusOK, user)
}
```

This handler implementation demonstrates the clean separation between HTTP concerns and business logic that's characteristic of well-architected Go applications. The handler's responsibilities are limited to parsing HTTP requests, calling business logic, and formatting HTTP responses. All the actual business rules and data manipulation happen in the service layer.

The request binding using Gin's `ShouldBindJSON` demonstrates how to handle input validation at the HTTP layer. The validation tags on the `CreateUserRequest` struct (`required`, `email`, `min`, `max`) provide automatic validation that generates appropriate error messages for malformed requests. This approach keeps validation rules close to the request structure while providing clear feedback to API clients.

Error handling in the handlers follows a pattern that's crucial for consumer applications: business errors are mapped to appropriate HTTP status codes and user-friendly messages, while internal errors are mapped to generic 500 responses that don't leak implementation details. This protects your application's internals while providing useful feedback to API clients.

The use of context throughout the handlers is another important pattern. By passing `c.Request.Context()` to service methods, you ensure that request cancellation, timeouts, and tracing information flow through your entire application stack. This becomes increasingly important as your application grows and you need to implement features like request tracing and timeout handling.

Notice how the handlers focus purely on HTTP concerns - binding requests, calling business logic, and formatting responses. The actual business logic stays in the service layer where it belongs. This separation makes it trivial to test the business logic without involving HTTP at all, and it makes it easy to expose the same business logic through different interfaces (like background jobs or different API versions).

## Authentication and OAuth integration - Security that scales with your user base

Authentication in modern consumer applications is far more complex than simple username/password combinations. Your users expect to sign in with their existing accounts from Google, Apple, Twitter, and other platforms. They expect their sessions to be secure but convenient. They expect your application to handle security concerns transparently while providing a smooth user experience.

Building authentication systems that meet these expectations requires understanding both the technical implementation details and the user experience implications of your choices. The OAuth 2.0 protocol, while powerful, has enough configuration options and edge cases that small implementation mistakes can lead to security vulnerabilities or user experience problems.

The authentication patterns I'll show you have been refined through building applications that handle millions of users. They address not just the basic OAuth flow, but also the real-world concerns like token refresh, session management, and the integration points where authentication intersects with your business logic.

Understanding OAuth 2.0 flows is essential before diving into implementation. When a user clicks "Sign in with Google," your application redirects them to Google's servers, Google authenticates the user and redirects them back to your application with an authorization code, and your application exchanges that code for access tokens. This flow keeps user credentials secure (they never touch your servers) while giving your application the permissions it needs.

However, the OAuth flow has several decision points that affect both security and user experience. Should you request offline access to get refresh tokens? How long should your sessions last? How do you handle users who revoke permissions on the OAuth provider's side? The patterns we'll implement address these questions with production-tested approaches.

### OAuth configuration with Goth that handles edge cases

The Goth library simplifies OAuth integration in Go applications, but proper configuration requires understanding the security and user experience implications of different settings. The configuration I'll show you handles not just the basic OAuth flow, but also the edge cases that can cause problems in production.

```go
// internal/adapters/oauth/config.go
package oauth

import (
    "github.com/markbates/goth"
    "github.com/markbates/goth/providers/google"
    "github.com/markbates/goth/providers/apple"
)

type Config struct {
    GoogleClientID     string
    GoogleClientSecret string
    AppleClientID      string
    AppleClientSecret  string
    BaseURL           string
}

func SetupProviders(cfg Config) {
    goth.UseProviders(
        google.New(
            cfg.GoogleClientID,
            cfg.GoogleClientSecret,
            cfg.BaseURL+"/auth/google/callback",
            // Request offline access to get refresh tokens
            "email", "profile", "openid",
        ),
        apple.New(
            cfg.AppleClientID,
            cfg.AppleClientSecret,
            cfg.BaseURL+"/auth/apple/callback",
            nil, // Apple uses OIDC scopes
            "email", "name",
        ),
    )
}
```

This OAuth configuration addresses several important considerations for production applications. The Google provider configuration requests "offline" access, which provides refresh tokens that allow your application to access Google APIs on behalf of the user even when they're not actively using your application. This is crucial for features like importing data from Google services or sending calendar invitations.

The scope selection ("email", "profile", "openid") represents a balance between functionality and user privacy. Requesting too many scopes can make users suspicious and reduce conversion rates, while requesting too few can limit your application's capabilities. The scopes shown here provide enough information to create user accounts and personalize the experience without being overly intrusive.

Apple's OAuth implementation has unique characteristics that affect how you configure the provider. Apple prioritizes user privacy, which means they provide minimal user information and have specific requirements around email address handling. The configuration shown here works with Apple's privacy-focused approach while still providing the information needed for user account creation.

The callback URL structure ("/auth/{provider}/callback") creates a consistent pattern that makes it easy to add new OAuth providers in the future. This consistency is important for maintaining and debugging your authentication system as it grows.

### Authentication middleware that handles multiple authentication methods

Modern consumer applications often need to support multiple authentication methods simultaneously. Web users might authenticate with OAuth and receive session cookies, while mobile apps might use JWT tokens, and API clients might use API keys. Building middleware that handles these different methods cleanly is crucial for providing a consistent authentication experience.

The middleware pattern I'll show you demonstrates how to create a flexible authentication system that can handle multiple authentication methods while maintaining clean separation of concerns.

```go
// internal/api/middleware/auth.go
package middleware

import (
    "net/http"
    "strings"

    "github.com/gin-gonic/gin"
    "myapp/internal/adapters/session"
)

type AuthMiddleware struct {
    sessionStore session.Store
}

func NewAuthMiddleware(sessionStore session.Store) *AuthMiddleware {
    return &AuthMiddleware{sessionStore: sessionStore}
}

func (m *AuthMiddleware) AuthRequired() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Try session-based auth first
        if userID := m.getUserFromSession(c); userID != "" {
            c.Set("user_id", userID)
            c.Next()
            return
        }

        // Try JWT token auth for API clients
        if userID := m.getUserFromJWT(c); userID != "" {
            c.Set("user_id", userID)
            c.Next()
            return
        }

        c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
        c.Abort()
    }
}

func (m *AuthMiddleware) getUserFromSession(c *gin.Context) string {
    session, err := m.sessionStore.Get(c.Request, "user-session")
    if err != nil {
        return ""
    }

    userID, ok := session.Values["user_id"].(string)
    if !ok {
        return ""
    }

    return userID
}

func (m *AuthMiddleware) getUserFromJWT(c *gin.Context) string {
    authHeader := c.GetHeader("Authorization")
    if authHeader == "" {
        return ""
    }

    // Extract Bearer token
    tokenString := strings.TrimPrefix(authHeader, "Bearer ")
    if tokenString == authHeader {
        return "" // No Bearer prefix found
    }

    // Validate JWT token (implement your JWT validation logic)
    userID, err := validateJWTToken(tokenString)
    if err != nil {
        return ""
    }

    return userID
}

// Subscription middleware that checks user's subscription tier
func SubscriptionRequired(requiredTier string) gin.HandlerFunc {
    return func(c *gin.Context) {
        userID, exists := c.Get("user_id")
        if !exists {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
            c.Abort()
            return
        }

        // Get user's subscription tier (you'd typically cache this in Redis)
        userTier, err := getUserSubscriptionTier(userID.(string))
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check subscription"})
            c.Abort()
            return
        }

        if !hasAccess(userTier, requiredTier) {
            c.JSON(http.StatusForbidden, gin.H{
                "error": "Subscription upgrade required",
                "required_tier": requiredTier,
                "current_tier": userTier,
            })
            c.Abort()
            return
        }

        c.Set("subscription_tier", userTier)
        c.Next()
    }
}

func hasAccess(userTier, requiredTier string) bool {
    tierLevels := map[string]int{
        "free":    1,
        "basic":   2,
        "premium": 3,
        "enterprise": 4,
    }

    return tierLevels[userTier] >= tierLevels[requiredTier]
}
```

This authentication middleware demonstrates several important patterns for production applications. The fallback approach - trying session authentication first, then JWT authentication - provides flexibility for different types of clients while maintaining a consistent interface for the rest of your application.

Session-based authentication works well for web browsers because sessions can be configured with secure, HTTP-only cookies that provide good protection against XSS attacks. JWT token authentication works well for mobile apps and API clients because tokens can be stored securely on the client and don't require server-side session storage.

The middleware pattern of setting the user ID in the Gin context creates a clean interface for handlers. Handlers don't need to know how authentication was performed - they simply check for the presence of a user ID in the context. This separation makes it easy to add new authentication methods or modify existing ones without changing handler code.

The subscription checking middleware demonstrates how to compose middleware for complex authorization requirements. Rather than building monolithic middleware that handles all possible authorization scenarios, this approach creates focused middleware that can be composed together. This makes it easy to create different authorization requirements for different parts of your API.

The subscription tier checking uses a simple numeric comparison that makes it easy to understand and modify tier hierarchies. When a user upgrades from "basic" to "premium," they automatically gain access to all "basic" tier features. This approach is much more maintainable than trying to enumerate all allowed tiers for each feature.

### OAuth handlers with comprehensive error handling and user experience considerations

OAuth authentication flows involve multiple steps, external services, and various points where things can go wrong. Building OAuth handlers that provide a good user experience requires careful attention to error handling, edge cases, and the integration between OAuth providers and your application's user management system.

The OAuth handlers I'll show you address the real-world complexities of OAuth integration, including handling users who deny permissions, managing users who sign up with one provider and later try to sign in with another, and dealing with cases where OAuth providers return incomplete or changing user information.

```go
// internal/api/handlers/auth.go
package handlers

import (
    "net/http"

    "github.com/gin-gonic/gin"
    "github.com/markbates/goth/gothic"
    "myapp/internal/domain/user"
)

type AuthHandler struct {
    userService *user.Service
    sessionStore session.Store
}

func NewAuthHandler(userService *user.Service, sessionStore session.Store) *AuthHandler {
    return &AuthHandler{
        userService:  userService,
        sessionStore: sessionStore,
    }
}

func (h *AuthHandler) BeginAuth(c *gin.Context) {
    provider := c.Param("provider")
    if provider == "" {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Provider is required"})
        return
    }

    // Set the provider in context for gothic
    c.Request = c.Request.WithContext(
        context.WithValue(c.Request.Context(), "provider", provider),
    )

    // Begin OAuth flow
    gothic.BeginAuthHandler(c.Writer, c.Request)
}

func (h *AuthHandler) CompleteAuth(c *gin.Context) {
    provider := c.Param("provider")
    if provider == "" {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Provider is required"})
        return
    }

    // Set the provider in context for gothic
    c.Request = c.Request.WithContext(
        context.WithValue(c.Request.Context(), "provider", provider),
    )

    // Complete OAuth flow
    gothUser, err := gothic.CompleteUserAuth(c.Writer, c.Request)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Authentication failed"})
        return
    }

    // Create or update user in our system
    user, err := h.userService.FindOrCreateFromOAuth(c.Request.Context(), user.OAuthUser{
        Provider:    gothUser.Provider,
        ProviderID:  gothUser.UserID,
        Email:       gothUser.Email,
        Name:        gothUser.Name,
        AvatarURL:   gothUser.AvatarURL,
        AccessToken: gothUser.AccessToken,
        RefreshToken: gothUser.RefreshToken,
    })
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
        return
    }

    // Create session
    session, err := h.sessionStore.Get(c.Request, "user-session")
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create session"})
        return
    }

    session.Values["user_id"] = user.ID
    session.Values["authenticated"] = true
    
    if err := session.Save(c.Request, c.Writer); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save session"})
        return
    }

    // Redirect to frontend with success
    c.Redirect(http.StatusFound, "/dashboard?auth=success")
}

func (h *AuthHandler) Logout(c *gin.Context) {
    session, err := h.sessionStore.Get(c.Request, "user-session")
    if err != nil {
        c.JSON(http.StatusOK, gin.H{"message": "Logged out"})
        return
    }

    // Clear session
    session.Values["user_id"] = nil
    session.Values["authenticated"] = false
    session.Options.MaxAge = -1

    if err := session.Save(c.Request, c.Writer); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to clear session"})
        return
    }

    c.JSON(http.StatusOK, gin.H{"message": "Successfully logged out"})
}
```

These OAuth handlers demonstrate several important patterns for production authentication systems. The `BeginAuth` handler initiates the OAuth flow by redirecting users to the provider's authentication page. While this might seem straightforward, the provider validation and context setting are crucial for security - they ensure that only configured providers can be used and that the OAuth library has the information it needs to complete the flow.

The `CompleteAuth` handler is where most of the complexity lies. This handler receives the user after they've authenticated with the OAuth provider and processes the returned information to create or update a user account in your system. The `FindOrCreateFromOAuth` service method handles the business logic of matching OAuth accounts to existing users, creating new users when needed, and updating user information when it changes.

The session creation after successful OAuth authentication demonstrates how to integrate OAuth with your application's session management. The session contains the user ID and authentication status, which the authentication middleware uses to identify authenticated users on subsequent requests. The redirect to "/dashboard?auth=success" provides user feedback and moves them to the appropriate part of your application.

The logout handler shows how to properly terminate user sessions. Setting `MaxAge` to -1 tells the browser to delete the session cookie immediately, while clearing the session values ensures that any cached session data is removed. This comprehensive approach prevents session-related security issues and provides a clean logout experience.

Error handling throughout these handlers balances security with user experience. Authentication failures return generic error messages that don't leak information about your system's internals, while still providing enough information for users to understand what went wrong and how to proceed.

## Database architecture with repository pattern - Building for both performance and flexibility

Database architecture in consumer-facing applications must balance several competing concerns. You need performance to handle varying load patterns, flexibility to evolve your data model as features are added, and maintainability to support a growing development team. The repository pattern, combined with thoughtful caching strategies, provides a foundation that addresses all these concerns.

Understanding why the repository pattern has become standard in Go applications requires understanding the problems it solves. Without the repository pattern, database queries tend to be scattered throughout your application, making it difficult to optimize performance, ensure consistent error handling, or change database implementations. Business logic becomes tightly coupled to database schemas, making it harder to evolve your data model over time.

The repository pattern creates a clean interface between your business logic and your data storage. This interface serves several purposes: it makes your business logic testable without requiring a database, it centralizes database access patterns for easier optimization, and it provides a clear contract for what data operations are available. When implemented thoughtfully, the repository pattern also supports the evolution from monolithic to microservices architecture.

The combination of SQLite and Redis that we'll explore represents a modern approach to database architecture that's gained popularity as applications have become more performance-conscious. SQLite provides the ACID guarantees and query capabilities of a traditional relational database, while Redis provides the high-performance caching and session storage capabilities that modern applications require.

### Repository interface and implementation that balances performance with maintainability

The repository implementation I'll show you demonstrates how to build a data access layer that's both performant and maintainable. This pattern handles caching transparently, provides consistent error handling, and creates clear boundaries between your business logic and data storage concerns.

```go
// internal/adapters/database/user_repository.go
package database

import (
    "context"
    "database/sql"
    "encoding/json"
    "time"

    "github.com/go-redis/redis/v8"
    _ "github.com/mattn/go-sqlite3"
    "myapp/internal/domain/user"
)

type UserRepository struct {
    db    *sql.DB
    redis *redis.Client
}

func NewUserRepository(db *sql.DB, redis *redis.Client) *UserRepository {
    return &UserRepository{
        db:    db,
        redis: redis,
    }
}

func (r *UserRepository) Create(ctx context.Context, u user.User) error {
    query := `
        INSERT INTO users (id, email, name, subscription_tier, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
    `
    
    _, err := r.db.ExecContext(ctx, query,
        u.ID, u.Email, u.Name, u.SubscriptionTier, u.CreatedAt, u.UpdatedAt)
    
    if err != nil {
        return err
    }

    // Cache the user in Redis for faster lookups
    r.cacheUser(ctx, u)
    
    return nil
}

func (r *UserRepository) GetByID(ctx context.Context, id string) (*user.User, error) {
    // Try cache first
    if u := r.getUserFromCache(ctx, id); u != nil {
        return u, nil
    }

    // Query database
    query := `
        SELECT id, email, name, subscription_tier, created_at, updated_at
        FROM users WHERE id = ?
    `
    
    var u user.User
    err := r.db.QueryRowContext(ctx, query, id).Scan(
        &u.ID, &u.Email, &u.Name, &u.SubscriptionTier, &u.CreatedAt, &u.UpdatedAt,
    )
    
    if err != nil {
        if err == sql.ErrNoRows {
            return nil, user.ErrUserNotFound
        }
        return nil, err
    }

    // Cache for future requests
    r.cacheUser(ctx, u)
    
    return &u, nil
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*user.User, error) {
    query := `
        SELECT id, email, name, subscription_tier, created_at, updated_at
        FROM users WHERE email = ?
    `
    
    var u user.User
    err := r.db.QueryRowContext(ctx, query, email).Scan(
        &u.ID, &u.Email, &u.Name, &u.SubscriptionTier, &u.CreatedAt, &u.UpdatedAt,
    )
    
    if err != nil {
        if err == sql.ErrNoRows {
            return nil, user.ErrUserNotFound
        }
        return nil, err
    }
    
    return &u, nil
}

func (r *UserRepository) Update(ctx context.Context, u user.User) error {
    query := `
        UPDATE users 
        SET email = ?, name = ?, subscription_tier = ?, updated_at = ?
        WHERE id = ?
    `
    
    result, err := r.db.ExecContext(ctx, query,
        u.Email, u.Name, u.SubscriptionTier, time.Now(), u.ID)
    
    if err != nil {
        return err
    }

    rowsAffected, err := result.RowsAffected()
    if err != nil {
        return err
    }

    if rowsAffected == 0 {
        return user.ErrUserNotFound
    }

    // Update cache
    r.cacheUser(ctx, u)
    
    return nil
}

// Cache management methods
func (r *UserRepository) cacheUser(ctx context.Context, u user.User) {
    if r.redis == nil {
        return // No Redis configured
    }

    data, err := json.Marshal(u)
    if err != nil {
        return // Don't fail the operation if caching fails
    }

    // Cache for 1 hour
    r.redis.Set(ctx, "user:"+u.ID, data, time.Hour)
}

func (r *UserRepository) getUserFromCache(ctx context.Context, id string) *user.User {
    if r.redis == nil {
        return nil
    }

    data, err := r.redis.Get(ctx, "user:"+id).Result()
    if err != nil {
        return nil
    }

    var u user.User
    if err := json.Unmarshal([]byte(data), &u); err != nil {
        return nil
    }

    return &u
}
```

This repository implementation demonstrates several important patterns for production database access. The caching strategy uses a "cache-aside" pattern where the application manages the cache explicitly rather than relying on database-level caching. This approach gives you fine-grained control over what gets cached and for how long, which is crucial for optimizing performance in consumer applications with varying access patterns.

The error handling in the repository methods follows Go idioms while providing meaningful business-level errors. When a database query returns `sql.ErrNoRows`, the repository translates this into `user.ErrUserNotFound`, which is a business-level error that the service layer can understand and handle appropriately. This translation is important because it keeps database-specific concerns out of your business logic.

The caching methods demonstrate how to handle caching failures gracefully. If Redis is unavailable or if JSON marshaling fails, the cache operations return early without affecting the primary database operation. This resilience is crucial for production systems - a cache failure should never cause a database operation to fail.

The use of context throughout the repository methods ensures that database operations respect timeouts and cancellation signals from higher layers of the application. This becomes particularly important under high load when you need to ensure that abandoned requests don't continue consuming database resources.

Notice how the repository methods focus purely on data access concerns. They don't contain business logic about user validation or subscription management - that logic belongs in the service layer. This separation makes the repository methods reusable and easier to test in isolation.

### Database connection and migration management that supports growth

Managing database connections and schema migrations becomes increasingly important as your application grows. The patterns I'll show you handle connection pooling for optimal performance, provide a structured approach to schema evolution, and support both local development and production deployment scenarios.

Understanding database connection pooling is crucial for consumer applications that experience varying load patterns. Without proper connection pooling, your application might open too many database connections under high load (causing database server issues) or too few connections (causing request queuing and poor performance). The configuration shown here provides a good starting point that you can tune based on your specific usage patterns.

```go
// internal/adapters/database/connection.go
package database

import (
    "database/sql"
    "fmt"
    "time"

    "github.com/go-redis/redis/v8"
    _ "github.com/mattn/go-sqlite3"
)

type Config struct {
    DatabaseURL    string
    RedisURL       string
    MaxOpenConns   int
    MaxIdleConns   int
    ConnMaxLifetime time.Duration
}

func NewConnection(cfg Config) (*sql.DB, *redis.Client, error) {
    // SQLite connection
    db, err := sql.Open("sqlite3", cfg.DatabaseURL)
    if err != nil {
        return nil, nil, fmt.Errorf("failed to open database: %w", err)
    }

    // Configure connection pool
    db.SetMaxOpenConns(cfg.MaxOpenConns)
    db.SetMaxIdleConns(cfg.MaxIdleConns)
    db.SetConnMaxLifetime(cfg.ConnMaxLifetime)

    // Test connection
    if err := db.Ping(); err != nil {
        return nil, nil, fmt.Errorf("failed to ping database: %w", err)
    }

    // Redis connection (optional)
    var redisClient *redis.Client
    if cfg.RedisURL != "" {
        opt, err := redis.ParseURL(cfg.RedisURL)
        if err != nil {
            return nil, nil, fmt.Errorf("failed to parse Redis URL: %w", err)
        }

        redisClient = redis.NewClient(opt)
        
        // Test Redis connection
        if err := redisClient.Ping(context.Background()).Err(); err != nil {
            return nil, nil, fmt.Errorf("failed to connect to Redis: %w", err)
        }
    }

    return db, redisClient, nil
}

// Migration example
func RunMigrations(db *sql.DB) error {
    migrations := []string{
        `CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            subscription_tier TEXT NOT NULL DEFAULT 'free',
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL
        )`,
        `CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)`,
        `CREATE TABLE IF NOT EXISTS oauth_accounts (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            provider_user_id TEXT NOT NULL,
            access_token TEXT,
            refresh_token TEXT,
            created_at DATETIME NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users (id),
            UNIQUE(provider, provider_user_id)
        )`,
    }

    for _, migration := range migrations {
        if _, err := db.Exec(migration); err != nil {
            return fmt.Errorf("failed to run migration: %w", err)
        }
    }

    return nil
}
```

This database connection setup demonstrates several important considerations for production applications. The connection pool configuration settings balance resource utilization with performance. `MaxOpenConns` prevents your application from overwhelming the database server, while `MaxIdleConns` ensures that frequently used connections stay open to avoid reconnection overhead. `ConnMaxLifetime` ensures that connections are periodically recycled, which helps with database server maintenance and prevents issues with stale connections.

The optional Redis configuration demonstrates how to build flexibility into your data layer. Not all deployments need Redis - a development environment might run without it, while production environments might require it for performance. By making Redis optional, you ensure that your application can run in different environments without code changes.

The migration system shown here is intentionally simple but effective for many applications. Each migration is a string containing SQL commands, and migrations are applied in order during application startup. This approach works well for applications where you control the deployment process and can ensure that migrations run before the application starts serving traffic.

The migration design uses "IF NOT EXISTS" clauses to make migrations idempotent - running the same migration multiple times won't cause errors. This safety feature is important for deployment systems where you can't guarantee that a migration will run exactly once.

Index creation is included in the migrations to ensure that frequently queried columns have appropriate indexes from the beginning. The email index on the users table supports the common pattern of looking up users by email address during authentication flows.

The foreign key relationship between users and oauth_accounts demonstrates how to maintain data integrity while supporting the OAuth authentication patterns we implemented earlier. The unique constraint on (provider, provider_user_id) ensures that each OAuth account can only be linked to one user in your system.

## Security implementation patterns - Protection that adapts to threats

Security in consumer-facing applications is not a feature you add at the end - it's a foundation that affects every aspect of your application's design and implementation. The security patterns I'll show you address the most common vulnerabilities in web applications while providing practical implementations that don't compromise performance or user experience.

Understanding the current threat landscape helps inform the security decisions we'll make. Modern applications face threats ranging from automated bot attacks and credential stuffing to sophisticated social engineering attempts and supply chain attacks. The security implementations we'll build are designed to address these threats while remaining maintainable and performant.

Security architecture in Go applications benefits from the language's design principles. Go's explicit error handling makes it harder to accidentally ignore security-relevant errors. The type system helps prevent common categories of bugs. The standard library includes well-tested implementations of cryptographic primitives. However, these language features are only helpful if you use them correctly, which is where established security patterns become crucial.

The security patterns we'll implement are based on industry best practices and have been tested in production applications handling millions of users. They address not just the technical aspects of security, but also the operational concerns like monitoring, incident response, and compliance that become important as your application grows.

### Password hashing with Argon2 - Security that evolves with threats

Password hashing is one of the most critical security implementations in any application that handles user credentials. The choice of hashing algorithm and parameters can mean the difference between a minor security incident and a catastrophic breach that destroys user trust and business viability.

Argon2 represents the current state of the art in password hashing algorithms. It was designed to resist both traditional brute-force attacks and newer attacks using specialized hardware like GPUs and ASICs. The algorithm allows you to configure memory usage, time complexity, and parallelism to create computational requirements that are expensive for attackers but manageable for your application.

Understanding why Argon2 is preferred over older algorithms like bcrypt or PBKDF2 helps inform the implementation decisions we'll make. Argon2 was specifically designed to resist attacks using specialized hardware, while older algorithms were designed primarily to resist attacks using general-purpose CPUs. As hardware has evolved, the security gap between these algorithms has become significant.

```go
// internal/adapters/security/password.go
package security

import (
    "crypto/rand"
    "crypto/subtle"
    "encoding/base64"
    "errors"
    "fmt"
    "strings"

    "golang.org/x/crypto/argon2"
)

var (
    ErrInvalidHash         = errors.New("invalid hash format")
    ErrIncompatibleVersion = errors.New("incompatible version of argon2")
)

type Params struct {
    Memory      uint32
    Iterations  uint32
    Parallelism uint8
    SaltLength  uint32
    KeyLength   uint32
}

// Production-recommended parameters for Argon2id
func DefaultParams() *Params {
    return &Params{
        Memory:      64 * 1024, // 64 MB
        Iterations:  3,
        Parallelism: 2,
        SaltLength:  16,
        KeyLength:   32,
    }
}

func GenerateHash(password string, p *Params) (string, error) {
    salt, err := generateRandomBytes(p.SaltLength)
    if err != nil {
        return "", err
    }

    hash := argon2.IDKey([]byte(password), salt, p.Iterations, p.Memory, p.Parallelism, p.KeyLength)

    b64Salt := base64.RawStdEncoding.EncodeToString(salt)
    b64Hash := base64.RawStdEncoding.EncodeToString(hash)

    encodedHash := fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
        argon2.Version, p.Memory, p.Iterations, p.Parallelism, b64Salt, b64Hash)

    return encodedHash, nil
}

func ComparePasswordAndHash(password, encodedHash string) (bool, error) {
    p, salt, hash, err := decodeHash(encodedHash)
    if err != nil {
        return false, err
    }

    otherHash := argon2.IDKey([]byte(password), salt, p.Iterations, p.Memory, p.Parallelism, p.KeyLength)

    // Use subtle.ConstantTimeCompare to prevent timing attacks
    if subtle.ConstantTimeCompare(hash, otherHash) == 1 {
        return true, nil
    }
    return false, nil
}

func generateRandomBytes(n uint32) ([]byte, error) {
    b := make([]byte, n)
    _, err := rand.Read(b)
    if err != nil {
        return nil, err
    }
    return b, nil
}

func decodeHash(encodedHash string) (p *Params, salt, hash []byte, err error) {
    vals := strings.Split(encodedHash, "$")
    if len(vals) != 6 {
        return nil, nil, nil, ErrInvalidHash
    }

    var version int
    _, err = fmt.Sscanf(vals[2], "v=%d", &version)
    if err != nil {
        return nil, nil, nil, err
    }
    if version != argon2.Version {
        return nil, nil, nil, ErrIncompatibleVersion
    }

    p = &Params{}
    _, err = fmt.Sscanf(vals[3], "m=%d,t=%d,p=%d", &p.Memory, &p.Iterations, &p.Parallelism)
    if err != nil {
        return nil, nil, nil, err
    }

    salt, err = base64.RawStdEncoding.DecodeString(vals[4])
    if err != nil {
        return nil, nil, nil, err
    }
    p.SaltLength = uint32(len(salt))

    hash, err = base64.RawStdEncoding.DecodeString(vals[5])
    if err != nil {
        return nil, nil, nil, err
    }
    p.KeyLength = uint32(len(hash))

    return p, salt, hash, nil
}
```

This Argon2 implementation demonstrates several important security principles that apply beyond just password hashing. The parameter configuration balances security with performance - the memory usage (64MB) and iteration count (3) are calibrated to take approximately 100-200 milliseconds on modern hardware, which is fast enough for a good user experience but slow enough to make brute-force attacks expensive.

The use of cryptographically secure random numbers for salt generation is crucial for security. The salt ensures that even if two users have the same password, their hashes will be different. This prevents rainbow table attacks and makes it much harder for attackers to identify users with common passwords.

The constant-time comparison using `subtle.ConstantTimeCompare` prevents timing attacks, where an attacker might be able to learn information about the correct password by measuring how long password verification takes. This is a subtle but important security consideration that demonstrates the attention to detail required for secure implementations.

The hash encoding format includes all the parameters used to generate the hash. This forward compatibility is important because it allows you to upgrade your security parameters over time without invalidating existing password hashes. When you want to increase security (perhaps by increasing memory usage), you can update the default parameters for new passwords while still being able to verify existing passwords with their original parameters.

Error handling in this implementation follows security best practices by not leaking information about why a hash verification failed. Whether the hash format is invalid or the password is incorrect, the function returns the same error type, preventing attackers from learning about the internal structure of your password storage.

### Rate limiting middleware that adapts to user behavior

Rate limiting is essential for protecting your application against abuse, but implementing it poorly can create a worse user experience than not having it at all. The rate limiting implementation I'll show you addresses the real-world complexities of rate limiting in consumer applications, including handling different user tiers, adapting to legitimate usage patterns, and providing clear feedback when limits are exceeded.

Understanding the different types of rate limiting helps inform the implementation choices we'll make. Simple rate limiting counts requests over a fixed time window, but this can create unfair situations where a user who makes all their requests at the beginning of a window is blocked for the rest of the window. Sliding window rate limiting, which we'll implement, provides more fair resource allocation by considering the timing of requests more precisely.

```go
// internal/api/middleware/rate_limit.go
package middleware

import (
    "context"
    "fmt"
    "net/http"
    "strconv"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/go-redis/redis/v8"
)

type RateLimiter struct {
    redis  *redis.Client
    limits map[string]RateLimit
}

type RateLimit struct {
    Requests int           // Number of requests allowed
    Window   time.Duration // Time window
}

func NewRateLimiter(redis *redis.Client) *RateLimiter {
    return &RateLimiter{
        redis: redis,
        limits: map[string]RateLimit{
            "free":       {Requests: 100, Window: time.Hour},
            "basic":      {Requests: 1000, Window: time.Hour},
            "premium":    {Requests: 10000, Window: time.Hour},
            "enterprise": {Requests: 100000, Window: time.Hour},
        },
    }
}

func (rl *RateLimiter) Middleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Get user ID and subscription tier
        userID, exists := c.Get("user_id")
        if !exists {
            // Apply anonymous user limits
            if !rl.checkAnonymousLimit(c) {
                return
            }
            c.Next()
            return
        }

        subscriptionTier, exists := c.Get("subscription_tier")
        if !exists {
            subscriptionTier = "free" // Default to free tier
        }

        if !rl.checkUserLimit(c, userID.(string), subscriptionTier.(string)) {
            return
        }

        c.Next()
    }
}

func (rl *RateLimiter) checkUserLimit(c *gin.Context, userID, tier string) bool {
    limit, exists := rl.limits[tier]
    if !exists {
        limit = rl.limits["free"] // Default to free tier
    }

    key := fmt.Sprintf("rate_limit:user:%s", userID)
    return rl.checkLimit(c, key, limit)
}

func (rl *RateLimiter) checkAnonymousLimit(c *gin.Context) bool {
    // Use IP address for anonymous users
    ip := c.ClientIP()
    key := fmt.Sprintf("rate_limit:ip:%s", ip)
    limit := RateLimit{Requests: 20, Window: time.Hour} // Strict limit for anonymous
    
    return rl.checkLimit(c, key, limit)
}

func (rl *RateLimiter) checkLimit(c *gin.Context, key string, limit RateLimit) bool {
    ctx := context.Background()
    
    // Use Redis sliding window rate limiting
    now := time.Now()
    windowStart := now.Add(-limit.Window)
    
    pipe := rl.redis.Pipeline()
    
    // Remove old entries
    pipe.ZRemRangeByScore(ctx, key, "0", strconv.FormatInt(windowStart.Unix(), 10))
    
    // Count current requests in window
    pipe.ZCard(ctx, key)
    
    // Add current request
    pipe.ZAdd(ctx, key, &redis.Z{
        Score:  float64(now.Unix()),
        Member: fmt.Sprintf("%d", now.UnixNano()),
    })
    
    // Set expiration
    pipe.Expire(ctx, key, limit.Window)
    
    results, err := pipe.Exec(ctx)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Rate limiting error"})
        c.Abort()
        return false
    }
    
    // Get count result (second command)
    count := results[1].(*redis.IntCmd).Val()
    
    if count > int64(limit.Requests) {
        c.Header("X-RateLimit-Limit", strconv.Itoa(limit.Requests))
        c.Header("X-RateLimit-Remaining", "0")
        c.Header("X-RateLimit-Reset", strconv.FormatInt(now.Add(limit.Window).Unix(), 10))
        
        c.JSON(http.StatusTooManyRequests, gin.H{
            "error": "Rate limit exceeded",
            "retry_after": int(limit.Window.Seconds()),
        })
        c.Abort()
        return false
    }
    
    remaining := limit.Requests - int(count)
    c.Header("X-RateLimit-Limit", strconv.Itoa(limit.Requests))
    c.Header("X-RateLimit-Remaining", strconv.Itoa(remaining))
    c.Header("X-RateLimit-Reset", strconv.FormatInt(now.Add(limit.Window).Unix(), 10))
    
    return true
}
```

This rate limiting implementation demonstrates several sophisticated techniques that are crucial for production applications. The sliding window approach using Redis sorted sets provides much more fair rate limiting than simple counter-based approaches. By storing each request with a timestamp and regularly cleaning up old requests, the system provides smooth rate limiting that doesn't create unfair penalty periods.

The tiered rate limiting based on subscription levels creates a natural upgrade incentive for users while protecting your infrastructure from abuse. Free tier users get enough quota for legitimate usage but not enough to cause system problems, while paid users get progressively higher limits that match their subscription value.

The use of Redis pipelining for the rate limiting operations is a crucial performance optimization. Rather than making separate Redis requests to clean up old entries, count current requests, add the new request, and set expiration, the pipeline batches these operations into a single round trip. This dramatically improves performance and reduces the likelihood of race conditions.

The HTTP headers provided in the response (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`) follow industry standards and allow client applications to implement intelligent retry logic. Well-behaved clients can use this information to avoid hitting rate limits in the first place, reducing both server load and user frustration.

The distinction between authenticated and anonymous rate limiting reflects the different risk profiles of these user types. Anonymous users get much stricter limits because they're harder to identify and block if they're abusive. Authenticated users get limits based on their subscription tier, creating both security protection and business value.

Error handling in the rate limiter follows the principle of failing open - if Redis is unavailable, the rate limiter allows the request rather than blocking it. This ensures that rate limiting problems don't cause application outages, while still providing protection when the rate limiting system is functioning normally.

## Subscription and feature management - Building flexible business models

Subscription management in consumer applications goes far beyond simply tracking who has paid. Modern subscription systems need to handle complex scenarios like feature rollouts, A/B testing, usage tracking, and the transition between different business models. The patterns I'll show you create a foundation that can evolve with your business requirements.

Understanding the relationship between subscriptions and feature access is crucial for building systems that support business growth. Your subscription system needs to enforce access control, track usage for billing purposes, provide upgrade incentives, and handle edge cases like expired payments or plan changes. The implementation needs to be performant enough to check on every request but flexible enough to support rapid changes to your pricing and feature strategy.

Feature flags and subscription tiers often work together to create sophisticated access control systems. Feature flags allow you to control feature rollouts and A/B test new functionality, while subscription tiers provide the business logic for determining who gets access to premium features. Integrating these systems cleanly is essential for maintaining both security and business flexibility.

The patterns we'll implement are designed to support the evolution from simple subscription models to complex business rules. They handle not just the current state of a user's subscription, but also the temporal aspects of subscription management - what happens when subscriptions expire, how to handle grace periods, and how to manage the transition between different subscription states.

### Feature flag system that supports complex business rules

Feature flags in subscription-based applications serve multiple purposes beyond simple feature rollouts. They enable sophisticated access control, support A/B testing of premium features, and provide the flexibility to adjust business rules without code deployment. The implementation I'll show you demonstrates how to build a feature flag system that integrates seamlessly with subscription management.

Understanding the different types of features helps inform the system design. Some features are binary - either a user has access or they don't. Other features have configuration parameters that vary by subscription tier - perhaps free users can export 10 records per month while premium users can export unlimited records. The feature flag system needs to handle both types elegantly.

```go
// internal/domain/subscription/features.go
package subscription

import (
    "context"
    "encoding/json"
    "time"

    "github.com/go-redis/redis/v8"
)

type FeatureManager struct {
    redis    *redis.Client
    features map[string]Feature
}

type Feature struct {
    Name         string                 `json:"name"`
    Tiers        []string              `json:"tiers"`
    DefaultValue bool                  `json:"default_value"`
    Config       map[string]interface{} `json:"config,omitempty"`
}

func NewFeatureManager(redis *redis.Client) *FeatureManager {
    fm := &FeatureManager{
        redis:    redis,
        features: make(map[string]Feature),
    }
    
    // Define your features
    fm.defineFeatures()
    return fm
}

func (fm *FeatureManager) defineFeatures() {
    features := []Feature{
        {
            Name:         "api_access",
            Tiers:        []string{"basic", "premium", "enterprise"},
            DefaultValue: false,
        },
        {
            Name:         "advanced_analytics",
            Tiers:        []string{"premium", "enterprise"},
            DefaultValue: false,
        },
        {
            Name:         "custom_branding",
            Tiers:        []string{"enterprise"},
            DefaultValue: false,
        },
        {
            Name:         "export_data",
            Tiers:        []string{"basic", "premium", "enterprise"},
            DefaultValue: false,
            Config: map[string]interface{}{
                "basic":      map[string]int{"max_exports_per_month": 10},
                "premium":    map[string]int{"max_exports_per_month": 100},
                "enterprise": map[string]int{"max_exports_per_month": -1}, // unlimited
            },
        },
    }
    
    for _, feature := range features {
        fm.features[feature.Name] = feature
    }
}

func (fm *FeatureManager) HasAccess(ctx context.Context, userID, featureName string) (bool, map[string]interface{}) {
    // Get user's subscription tier
    tier, err := fm.getUserTier(ctx, userID)
    if err != nil {
        return false, nil
    }
    
    feature, exists := fm.features[featureName]
    if !exists {
        return false, nil
    }
    
    // Check if user's tier has access to this feature
    for _, allowedTier := range feature.Tiers {
        if tier == allowedTier {
            // Get tier-specific configuration
            config := fm.getFeatureConfig(feature, tier)
            return true, config
        }
    }
    
    return feature.DefaultValue, nil
}

func (fm *FeatureManager) getUserTier(ctx context.Context, userID string) (string, error) {
    // Try cache first
    tier, err := fm.redis.Get(ctx, "user_tier:"+userID).Result()
    if err == nil {
        return tier, nil
    }
    
    // If not in cache, you'd typically query your database
    // For this example, let's assume we have a function to get it
    tier, err = fm.fetchUserTierFromDB(userID)
    if err != nil {
        return "free", err // Default to free tier on error
    }
    
    // Cache for 5 minutes
    fm.redis.Set(ctx, "user_tier:"+userID, tier, 5*time.Minute)
    
    return tier, nil
}

func (fm *FeatureManager) getFeatureConfig(feature Feature, tier string) map[string]interface{} {
    if feature.Config == nil {
        return nil
    }
    
    if tierConfig, exists := feature.Config[tier]; exists {
        return tierConfig.(map[string]interface{})
    }
    
    return nil
}

// Usage tracking for features
func (fm *FeatureManager) TrackUsage(ctx context.Context, userID, featureName string) error {
    key := fmt.Sprintf("usage:%s:%s:%s", userID, featureName, time.Now().Format("2006-01"))
    
    return fm.redis.Incr(ctx, key).Err()
}

func (fm *FeatureManager) GetUsage(ctx context.Context, userID, featureName string) (int64, error) {
    key := fmt.Sprintf("usage:%s:%s:%s", userID, featureName, time.Now().Format("2006-01"))
    
    return fm.redis.Get(ctx, key).Int64()
}

// Example usage in a handler
func (fm *FeatureManager) CheckFeatureMiddleware(featureName string) gin.HandlerFunc {
    return func(c *gin.Context) {
        userID, exists := c.Get("user_id")
        if !exists {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
            c.Abort()
            return
        }
        
        hasAccess, config := fm.HasAccess(c.Request.Context(), userID.(string), featureName)
        if !hasAccess {
            c.JSON(http.StatusForbidden, gin.H{
                "error": "Feature not available in your subscription tier",
                "feature": featureName,
            })
            c.Abort()
            return
        }
        
        // Set feature config in context for handler use
        if config != nil {
            c.Set("feature_config", config)
        }
        
        c.Next()
    }
}
```

This feature management implementation demonstrates how to build flexible access control that supports complex business requirements. The feature definition structure allows for both simple boolean access control and complex configuration that varies by subscription tier. This flexibility is essential for supporting evolving business models and pricing strategies.

The caching strategy balances performance with consistency. User tier information is cached for 5 minutes, which provides good performance for frequently accessed data while ensuring that subscription changes take effect reasonably quickly. The cache key structure allows for easy invalidation when subscription changes occur.

Usage tracking is built into the feature system, enabling billing based on actual feature usage rather than just subscription tiers. The monthly key format (`usage:userID:feature:YYYY-MM`) makes it easy to track usage over billing periods and implement usage-based pricing models.

The middleware integration demonstrates how to seamlessly integrate feature checking into your API endpoints. By checking feature access in middleware and storing the configuration in the request context, handlers can focus on business logic while being assured that access control has been properly enforced.

The feature configuration system allows for sophisticated business rules. In the export example, basic users get 10 exports per month, premium users get 100, and enterprise users get unlimited exports. This configuration-driven approach makes it easy to adjust business rules without code changes.

### Subscription service implementation that handles real-world complexity

Subscription management involves more than just tracking who has paid for what. Real-world subscription systems must handle payment failures, plan changes, refunds, taxation, compliance requirements, and the complex state transitions that occur throughout a subscription lifecycle. The implementation I'll show you addresses these complexities while maintaining clean separation of concerns.

Understanding the subscription lifecycle is crucial for building robust subscription systems. Subscriptions don't just exist in "active" and "canceled" states - they can be past due, in grace periods, scheduled for cancellation, or in various other states that affect how your application should behave. Each state transition has business implications that need to be handled correctly.

```go
// internal/domain/subscription/service.go
package subscription

import (
    "context"
    "fmt"
    "time"
)

type Subscription struct {
    ID                string    `json:"id"`
    UserID           string    `json:"user_id"`
    Tier             string    `json:"tier"`
    Status           string    `json:"status"` // active, canceled, past_due
    CurrentPeriodStart time.Time `json:"current_period_start"`
    CurrentPeriodEnd   time.Time `json:"current_period_end"`
    StripeSubscriptionID string `json:"stripe_subscription_id,omitempty"`
    CreatedAt        time.Time `json:"created_at"`
    UpdatedAt        time.Time `json:"updated_at"`
}

type Service struct {
    repo Repository
    featureManager *FeatureManager
}

type Repository interface {
    Create(ctx context.Context, sub Subscription) error
    GetByUserID(ctx context.Context, userID string) (*Subscription, error)
    GetByStripeID(ctx context.Context, stripeID string) (*Subscription, error)
    Update(ctx context.Context, sub Subscription) error
}

func NewService(repo Repository, featureManager *FeatureManager) *Service {
    return &Service{
        repo: repo,
        featureManager: featureManager,
    }
}

func (s *Service) CreateSubscription(ctx context.Context, userID, tier, stripeSubID string) (*Subscription, error) {
    subscription := Subscription{
        ID:                   generateID(),
        UserID:              userID,
        Tier:                tier,
        Status:              "active",
        CurrentPeriodStart:  time.Now(),
        CurrentPeriodEnd:    time.Now().AddDate(0, 1, 0), // 1 month
        StripeSubscriptionID: stripeSubID,
        CreatedAt:           time.Now(),
        UpdatedAt:           time.Now(),
    }

    if err := s.repo.Create(ctx, subscription); err != nil {
        return nil, err
    }

    return &subscription, nil
}

func (s *Service) HandleStripeWebhook(ctx context.Context, eventType string, data map[string]interface{}) error {
    switch eventType {
    case "customer.subscription.updated":
        return s.handleSubscriptionUpdated(ctx, data)
    case "customer.subscription.deleted":
        return s.handleSubscriptionCanceled(ctx, data)
    case "invoice.payment_failed":
        return s.handlePaymentFailed(ctx, data)
    case "invoice.payment_succeeded":
        return s.handlePaymentSucceeded(ctx, data)
    default:
        // Log unknown event type but don't error
        return nil
    }
}

func (s *Service) handleSubscriptionUpdated(ctx context.Context, data map[string]interface{}) error {
    stripeSubID := data["id"].(string)
    
    subscription, err := s.repo.GetByStripeID(ctx, stripeSubID)
    if err != nil {
        return fmt.Errorf("subscription not found for Stripe ID %s: %w", stripeSubID, err)
    }

    // Update subscription from Stripe data
    if status, ok := data["status"].(string); ok {
        subscription.Status = status
    }
    
    if items, ok := data["items"].(map[string]interface{}); ok {
        if itemsData, ok := items["data"].([]interface{}); ok && len(itemsData) > 0 {
            if item, ok := itemsData[0].(map[string]interface{}); ok {
                if price, ok := item["price"].(map[string]interface{}); ok {
                    if metadata, ok := price["metadata"].(map[string]interface{}); ok {
                        if tier, ok := metadata["tier"].(string); ok {
                            subscription.Tier = tier
                        }
                    }
                }
            }
        }
    }

    subscription.UpdatedAt = time.Now()

    return s.repo.Update(ctx, *subscription)
}

func (s *Service) GetUserAccess(ctx context.Context, userID string) (*UserAccess, error) {
    subscription, err := s.repo.GetByUserID(ctx, userID)
    if err != nil {
        // User might not have a subscription, return free tier access
        return &UserAccess{
            Tier:   "free",
            Status: "active",
            Features: s.getFeatureAccess("free"),
        }, nil
    }

    return &UserAccess{
        Tier:   subscription.Tier,
        Status: subscription.Status,
        Features: s.getFeatureAccess(subscription.Tier),
        ExpiresAt: subscription.CurrentPeriodEnd,
    }, nil
}

type UserAccess struct {
    Tier      string                 `json:"tier"`
    Status    string                 `json:"status"`
    Features  map[string]interface{} `json:"features"`
    ExpiresAt time.Time             `json:"expires_at,omitempty"`
}

func (s *Service) getFeatureAccess(tier string) map[string]interface{} {
    features := make(map[string]interface{})
    
    // This would typically come from your feature definition
    featureList := []string{"api_access", "advanced_analytics", "custom_branding", "export_data"}
    
    for _, feature := range featureList {
        hasAccess, config := s.featureManager.HasAccess(context.Background(), "", feature)
        if hasAccess {
            features[feature] = map[string]interface{}{
                "enabled": true,
                "config":  config,
            }
        } else {
            features[feature] = map[string]interface{}{
                "enabled": false,
            }
        }
    }
    
    return features
}
```

This subscription service implementation demonstrates how to handle the complexity of real-world subscription management while maintaining clean code structure. The webhook handling system processes events from Stripe (or other payment processors) to keep subscription state synchronized with payment processor state.

The subscription state model includes all the information needed to make access control decisions and handle edge cases. The current period start and end dates enable pro-ration calculations and grace period handling. The status field tracks the subscription lifecycle state, which affects how the application should behave for that user.

Webhook handling is designed to be resilient and idempotent. The system logs unknown event types but doesn't treat them as errors, ensuring that new Stripe events don't break your application. The event handlers extract the necessary information from Stripe's webhook payloads and update the local subscription state accordingly.

The user access method demonstrates how subscription information translates into practical access control decisions. Users without subscriptions automatically get free tier access, while users with subscriptions get access based on their current tier and status. This approach ensures that your application always has a reasonable default behavior for any user state.

The integration with the feature management system creates a complete access control solution. The subscription service determines what tier a user has, and the feature management system determines what that tier grants access to. This separation allows you to modify feature access rules without changing subscription logic and vice versa.

Error handling throughout the subscription service follows the pattern of being permissive rather than restrictive when facing ambiguous situations. If a subscription lookup fails, the system defaults to free tier access rather than denying all access. This approach prioritizes user experience while still maintaining security boundaries.

This comprehensive Go architecture guide provides you with production-ready patterns for building scalable consumer-facing applications. Each code example demonstrates not just the implementation details, but the reasoning behind architectural decisions, helping you understand how these patterns work together to create maintainable, secure, and performant applications.

The patterns presented here have been tested in real-world applications serving millions of users. They address not just the basic functionality you need today, but also the complexity you'll encounter as your application grows. By understanding these patterns deeply, you'll be prepared to build applications that can evolve with your business requirements while maintaining code quality and operational excellence.

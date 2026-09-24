using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.IdentityModel.Tokens;
using Silen.Api.Health;
using Silen.Api.HostedServices;
using Silen.Common.Contracts;
using Silen.Common.Enums;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Data;
using Silen.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection(JwtOptions.SectionName));
builder.Services.Configure<GoogleAuthOptions>(builder.Configuration.GetSection(GoogleAuthOptions.SectionName));
builder.Services.Configure<AppleAuthOptions>(builder.Configuration.GetSection(AppleAuthOptions.SectionName));
builder.Services.Configure<OpenRouterOptions>(builder.Configuration.GetSection(OpenRouterOptions.SectionName));
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection(SmtpOptions.SectionName));
builder.Services.Configure<EncryptionOptions>(builder.Configuration.GetSection(EncryptionOptions.SectionName));
builder.Services.Configure<AdminAuthOptions>(builder.Configuration.GetSection(AdminAuthOptions.SectionName));
builder.Services.Configure<NotificationPublishOptions>(builder.Configuration.GetSection(NotificationPublishOptions.SectionName));
builder.Services.Configure<PushNotificationOptions>(builder.Configuration.GetSection(PushNotificationOptions.SectionName));
builder.Services.Configure<ReviewerBypassOptions>(builder.Configuration.GetSection(ReviewerBypassOptions.SectionName));
builder.Services.Configure<ImageUploadOptions>(builder.Configuration.GetSection(ImageUploadOptions.SectionName));
builder.Services.Configure<AppStoreServerOptions>(builder.Configuration.GetSection(AppStoreServerOptions.SectionName));
builder.Services.Configure<GooglePlayOptions>(builder.Configuration.GetSection(GooglePlayOptions.SectionName));

builder.Services.AddSilenData();
builder.Services.AddSilenServices();
builder.Services.AddHostedService<NotificationPublishBackgroundService>();

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// JSON-over-the-wire is the bulk of API traffic; Brotli/Gzip cuts it substantially
// for the larger list payloads (splits, analytics) with no client changes.
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
});

// Liveness never touches the database; readiness does. nginx / an orchestrator can
// use /health/ready to drain an instance whose SQL connection is down.
builder.Services.AddHealthChecks()
    .AddCheck<SqlHealthCheck>("database", tags: new[] { "ready" });

// JSON request bodies are small. Without a cap a client can stream an
// arbitrarily large body and pin memory before model binding ever runs.
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 1 * 1024 * 1024;
});

// [ApiController] runs model validation before the action. Keep the app's
// single response envelope there: the Flutter client reads { success, message },
// so a raw ValidationProblemDetails body would surface as "Something went wrong"
// instead of the field-level reason.
builder.Services.Configure<ApiBehaviorOptions>(options =>
{
    options.InvalidModelStateResponseFactory = context =>
    {
        var message = context.ModelState
            .SelectMany(entry => (IEnumerable<ModelError>?)entry.Value?.Errors ?? Enumerable.Empty<ModelError>())
            .Select(error => error.ErrorMessage)
            .FirstOrDefault(candidate => !string.IsNullOrWhiteSpace(candidate))
            ?? "Please check the information you entered and try again.";

        return new BadRequestObjectResult(ApiResponse.Fail(message));
    };
});

// Request throttling. Without this the anonymous auth endpoints (device login,
// register/start, resend, email login) and the billable AI endpoint can be hit
// without limit - credential stuffing, guest-account spam, email bombing, code
// brute force and OpenRouter spend. Every policy partitions per client IP (which
// ForwardedHeaders rewrites to the real client behind nginx) or, where the caller
// is authenticated, per user id. Rejections keep the app's uniform envelope so the
// Flutter client's ApiException path handles a 429 like any other failure.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.OnRejected = async (context, cancellationToken) =>
    {
        context.HttpContext.Response.ContentType = "application/json";
        await context.HttpContext.Response.WriteAsJsonAsync(
            ApiResponse.Fail("Too many requests. Please try again later."), cancellationToken);
    };

    options.AddPolicy(RateLimitPolicies.Auth, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            ClientPartitionKey(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 20,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));

    options.AddPolicy(RateLimitPolicies.AdminAuth, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            ClientPartitionKey(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(5),
                QueueLimit = 0,
                AutoReplenishment = true
            }));

    options.AddPolicy(RateLimitPolicies.Analytics, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            AuthenticatedPartitionKey(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
                AutoReplenishment = true
            }));

    // Generous: real store traffic (renewals, refunds, retries) is legitimate and
    // bursty around billing cycles, but this is still an anonymous endpoint that
    // shouldn't be left fully unbounded against abuse.
    options.AddPolicy(RateLimitPolicies.Webhooks, httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            ClientPartitionKey(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
});

var jwtOptions = builder.Configuration.GetSection(JwtOptions.SectionName).Get<JwtOptions>() ?? new JwtOptions();

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        // Without this, the handler remaps "sub" to ClaimTypes.NameIdentifier
        // (and "email" similarly), breaking ClaimsPrincipalExtensions.GetUserId.
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtOptions.Issuer,
            ValidateAudience = true,
            ValidAudience = jwtOptions.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtOptions.SigningKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(AuthorizationPolicies.RequireLinkedAccount, policy =>
        policy.RequireClaim(JwtTokenFactory.TierClaimType, AccountTier.Registered.ToString()));
});

// Development-only CORS for the static site in website/. Locally the site is either
// served by a throwaway static file server on some localhost port, or opened straight
// from disk as a file:// URL (see admin-auth.js's defaultDevApiBase) - the browser sends
// Origin: null for the latter, which is not a URI Uri.TryCreate can parse, so it needs
// its own check. Either way the API runs on :5080, so admin sign-in needs a cross-origin
// fetch *with* credentials (the session cookie). Only outside Production - in production
// the site and the API are the same origin, so CORS never applies.
const string DevSiteCorsPolicy = "DevLocalSite";

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options =>
    {
        options.AddPolicy(DevSiteCorsPolicy, policy => policy
            .SetIsOriginAllowed(origin =>
                origin == "null" ||
                (Uri.TryCreate(origin, UriKind.Absolute, out var uri) &&
                (uri.Host == "localhost" || uri.Host == "127.0.0.1")))
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials());
    });
}

var app = builder.Build();

app.UseResponseCompression();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    // Production is HTTPS-only (nginx terminates TLS). Skipped in development so a
    // plain-http local stack is never pinned to HSTS by a browser.
    app.UseHsts();
}

app.UseHttpsRedirection();

// Serves uploaded images back out under /uploads. In production nginx's
// images.sila.fitness vhost reads the same directory straight off disk and this
// route never gets hit for a real request - it exists so images.sila.fitness's
// DNS/TLS being briefly unready (or plain local development, which has no nginx
// at all) still has a working URL to fall back to.
var imageUploadOptions = builder.Configuration.GetSection(ImageUploadOptions.SectionName).Get<ImageUploadOptions>() ?? new ImageUploadOptions();
Directory.CreateDirectory(imageUploadOptions.StoragePath);
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(Path.GetFullPath(imageUploadOptions.StoragePath)),
    RequestPath = "/uploads"
});

// Built-in artwork that ships with the API (StaticAssets/, copied to the publish
// output) - today the auto-assigned split hero images, requested by the app as
// {API_BASE_URL}/static/splits/{dark|light}/{key}.jpg. Under /api so it rides the
// same nginx proxy as every API call. Clients may cache for a week without
// asking; after that the ETag/Last-Modified the middleware emits turn the
// revalidation into a body-less 304.
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(
        Path.Combine(app.Environment.ContentRootPath, "StaticAssets")),
    RequestPath = "/api/static",
    OnPrepareResponse = context =>
        context.Context.Response.Headers.CacheControl = "public, max-age=604800, stale-while-revalidate=86400"
});

// Baseline response hardening for the API. The static site / admin console get
// their own headers from nginx; these keep direct API responses safe too.
app.Use(async (context, next) =>
{
    var headers = context.Response.Headers;
    headers["X-Content-Type-Options"] = "nosniff";
    headers["X-Frame-Options"] = "DENY";
    headers["Referrer-Policy"] = "no-referrer";
    headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()";
    await next();
});

if (app.Environment.IsDevelopment())
{
    app.UseCors(DevSiteCorsPolicy);
}

app.UseAuthentication();
// After authentication so the analytics policy can partition per user, and after
// the automatic UseRouting so the endpoint's [EnableRateLimiting] metadata is known.
app.UseRateLimiter();
app.UseAuthorization();

app.MapControllers();

app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

app.Run();

// Rate-limit partition keys. RemoteIpAddress is the real client because the
// production container sets ASPNETCORE_FORWARDEDHEADERS_ENABLED, which rewrites it
// from X-Forwarded-For. "unknown" groups the (rare) unparseable cases together.
static string ClientPartitionKey(HttpContext httpContext) =>
    httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";

static string AuthenticatedPartitionKey(HttpContext httpContext) =>
    httpContext.User?.FindFirst("sub")?.Value
    ?? httpContext.Connection.RemoteIpAddress?.ToString()
    ?? "unknown";

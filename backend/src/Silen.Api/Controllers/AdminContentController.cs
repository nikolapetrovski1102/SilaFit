using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// Reference content management for the console - exercises, meal suggestions,
/// subscription plans and the split library - plus the read-only user list.
///
/// Same authentication shape as <see cref="AdminRbacController"/> and deliberately
/// not [Authorize]: the credential is the HttpOnly session cookie, not a bearer
/// token. Every action here additionally requires a specific content.* permission
/// on top of just being signed in - <see cref="Silen.Services.Helpers.AdminPermissionGuard"/>
/// enforces that inside the service layer and throws a 403 when it's missing, so
/// there is nothing to check here beyond passing the cookie through.
/// </summary>
[ApiController]
[Route("api/admin/content")]
public sealed class AdminContentController(
    IAdminConsoleService consoleService,
    IOptions<AdminAuthOptions> adminAuthOptions,
    ILogger<AdminContentController> logger) : ControllerBase
{
    private string? SessionToken => AdminSessionCookie.Read(Request, adminAuthOptions.Value);

    private string? ClientIp => HttpContext.Connection.RemoteIpAddress?.ToString();

    /* ------------------------------- exercises ------------------------------ */

    [HttpGet("exercises")]
    public async Task<IActionResult> GetExercises(CancellationToken cancellationToken) =>
        (await consoleService.GetExercisesAsync(SessionToken, cancellationToken)).ToActionResult(logger);

    [HttpPost("exercises")]
    public async Task<IActionResult> SaveExercise([FromBody] AdminExerciseUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveExerciseAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("exercises/{exerciseId:guid}")]
    public async Task<IActionResult> DeleteExercise(Guid exerciseId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteExerciseAsync(SessionToken, exerciseId, ClientIp, cancellationToken)).ToActionResult(logger);

    /* --------------------------------- images -------------------------------- */

    // IFormFile is bound from the multipart body automatically even under
    // [ApiController]'s normally-body-first inference rules - no [FromForm] needed.
    // The Kestrel-wide 1MB body cap (Program.cs) is overridden per-request here.
    [HttpPost("images")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> UploadImage(IFormFile? file, CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(ApiResponse.Fail("Choose an image to upload."));
        }

        await using var stream = file.OpenReadStream();
        var upload = new ImageUploadRequest(stream, file.FileName, file.ContentType, file.Length);
        return (await consoleService.UploadImageAsync(SessionToken, upload, ClientIp, cancellationToken)).ToActionResult(logger);
    }

    /* --------------------------- meal suggestions ---------------------------- */

    [HttpGet("meal-suggestions")]
    public async Task<IActionResult> GetMealSuggestions(
        [FromQuery] int? suggestedMonth,
        [FromQuery] string? mealType,
        [FromQuery] string? search,
        CancellationToken cancellationToken) =>
        (await consoleService.GetMealSuggestionsAsync(SessionToken, suggestedMonth, mealType, search, cancellationToken)).ToActionResult(logger);

    [HttpPost("meal-suggestions")]
    public async Task<IActionResult> SaveMealSuggestion([FromBody] AdminMealSuggestionUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveMealSuggestionAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("meal-suggestions/{mealSuggestionId:guid}")]
    public async Task<IActionResult> DeleteMealSuggestion(Guid mealSuggestionId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteMealSuggestionAsync(SessionToken, mealSuggestionId, ClientIp, cancellationToken)).ToActionResult(logger);

    /* --------------------------------- plans -------------------------------- */

    [HttpGet("plans")]
    public async Task<IActionResult> GetPlans(CancellationToken cancellationToken) =>
        (await consoleService.GetPlansAsync(SessionToken, cancellationToken)).ToActionResult(logger);

    [HttpGet("plans/{planId:guid}/features")]
    public async Task<IActionResult> GetPlanFeatures(Guid planId, CancellationToken cancellationToken) =>
        (await consoleService.GetPlanFeaturesAsync(SessionToken, planId, cancellationToken)).ToActionResult(logger);

    [HttpPost("plans")]
    public async Task<IActionResult> SavePlan([FromBody] AdminPlanUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SavePlanAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("plans/{planId:guid}")]
    public async Task<IActionResult> DeletePlan(Guid planId, CancellationToken cancellationToken) =>
        (await consoleService.DeletePlanAsync(SessionToken, planId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPost("plans/features")]
    public async Task<IActionResult> SavePlanFeature([FromBody] AdminPlanFeatureUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SavePlanFeatureAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("plans/features/{planFeatureId:guid}")]
    public async Task<IActionResult> DeletePlanFeature(Guid planFeatureId, CancellationToken cancellationToken) =>
        (await consoleService.DeletePlanFeatureAsync(SessionToken, planFeatureId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpGet("plans/{planId:guid}/entitlements")]
    public async Task<IActionResult> GetPlanEntitlements(Guid planId, CancellationToken cancellationToken) =>
        (await consoleService.GetPlanEntitlementsAsync(SessionToken, planId, cancellationToken)).ToActionResult(logger);

    [HttpPut("plans/entitlements")]
    public async Task<IActionResult> SavePlanEntitlements([FromBody] AdminPlanEntitlementsUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SavePlanEntitlementsAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    /* -------------------------------- splits -------------------------------- */

    [HttpGet("splits")]
    public async Task<IActionResult> GetSplits(CancellationToken cancellationToken) =>
        (await consoleService.GetSplitsAsync(SessionToken, cancellationToken)).ToActionResult(logger);

    [HttpGet("splits/{splitId:guid}")]
    public async Task<IActionResult> GetSplitDetail(Guid splitId, CancellationToken cancellationToken) =>
        (await consoleService.GetSplitDetailAsync(SessionToken, splitId, cancellationToken)).ToActionResult(logger);

    [HttpPost("splits")]
    public async Task<IActionResult> SaveSplit([FromBody] AdminSplitUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveSplitAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("splits/{splitId:guid}")]
    public async Task<IActionResult> DeleteSplit(Guid splitId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteSplitAsync(SessionToken, splitId, ClientIp, cancellationToken)).ToActionResult(logger);

    /* --------------------------- split assignments --------------------------- */

    [HttpGet("splits/{splitId:guid}/assignments")]
    public async Task<IActionResult> GetSplitAssignments(Guid splitId, CancellationToken cancellationToken) =>
        (await consoleService.GetSplitAssignmentsAsync(SessionToken, splitId, cancellationToken)).ToActionResult(logger);

    [HttpPost("splits/assignments")]
    public async Task<IActionResult> AssignSplit([FromBody] AdminSplitAssignRequest request, CancellationToken cancellationToken) =>
        (await consoleService.AssignSplitAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("splits/{splitId:guid}/assignments/{userId:guid}")]
    public async Task<IActionResult> RemoveSplitAssignment(Guid splitId, Guid userId, CancellationToken cancellationToken) =>
        (await consoleService.RemoveSplitAssignmentAsync(SessionToken, splitId, userId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPost("splits/days")]
    public async Task<IActionResult> SaveSplitDay([FromBody] AdminSplitDayUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveSplitDayAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("splits/days/{splitDayId:guid}")]
    public async Task<IActionResult> DeleteSplitDay(Guid splitDayId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteSplitDayAsync(SessionToken, splitDayId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPost("splits/days/exercises")]
    public async Task<IActionResult> SaveSplitDayExercise([FromBody] AdminSplitDayExerciseUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveSplitDayExerciseAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("splits/days/exercises/{splitDayExerciseId:guid}")]
    public async Task<IActionResult> DeleteSplitDayExercise(Guid splitDayExerciseId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteSplitDayExerciseAsync(SessionToken, splitDayExerciseId, ClientIp, cancellationToken)).ToActionResult(logger);

    /* ------------------------------- diet plans ------------------------------ */

    [HttpGet("diet-plans")]
    public async Task<IActionResult> GetDietPlans(CancellationToken cancellationToken) =>
        (await consoleService.GetDietPlansAsync(SessionToken, cancellationToken)).ToActionResult(logger);

    [HttpGet("diet-plans/{dietPlanId:guid}")]
    public async Task<IActionResult> GetDietPlanDetail(Guid dietPlanId, CancellationToken cancellationToken) =>
        (await consoleService.GetDietPlanDetailAsync(SessionToken, dietPlanId, cancellationToken)).ToActionResult(logger);

    [HttpPost("diet-plans")]
    public async Task<IActionResult> SaveDietPlan([FromBody] AdminDietPlanUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveDietPlanAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("diet-plans/{dietPlanId:guid}")]
    public async Task<IActionResult> DeleteDietPlan(Guid dietPlanId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteDietPlanAsync(SessionToken, dietPlanId, ClientIp, cancellationToken)).ToActionResult(logger);

    /* ------------------------ diet plan assignments -------------------------- */

    [HttpGet("diet-plans/{dietPlanId:guid}/assignments")]
    public async Task<IActionResult> GetDietPlanAssignments(Guid dietPlanId, CancellationToken cancellationToken) =>
        (await consoleService.GetDietPlanAssignmentsAsync(SessionToken, dietPlanId, cancellationToken)).ToActionResult(logger);

    [HttpPost("diet-plans/assignments")]
    public async Task<IActionResult> AssignDietPlan([FromBody] AdminDietPlanAssignRequest request, CancellationToken cancellationToken) =>
        (await consoleService.AssignDietPlanAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("diet-plans/{dietPlanId:guid}/assignments/{userId:guid}")]
    public async Task<IActionResult> RemoveDietPlanAssignment(Guid dietPlanId, Guid userId, CancellationToken cancellationToken) =>
        (await consoleService.RemoveDietPlanAssignmentAsync(SessionToken, dietPlanId, userId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPost("diet-plans/days")]
    public async Task<IActionResult> SaveDietPlanDay([FromBody] AdminDietPlanDayUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveDietPlanDayAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("diet-plans/days/{dietPlanDayId:guid}")]
    public async Task<IActionResult> DeleteDietPlanDay(Guid dietPlanDayId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteDietPlanDayAsync(SessionToken, dietPlanDayId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPost("diet-plans/meals")]
    public async Task<IActionResult> SaveDietPlanMeal([FromBody] AdminDietPlanMealUpsertRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SaveDietPlanMealAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("diet-plans/meals/{dietPlanMealId:guid}")]
    public async Task<IActionResult> DeleteDietPlanMeal(Guid dietPlanMealId, CancellationToken cancellationToken) =>
        (await consoleService.DeleteDietPlanMealAsync(SessionToken, dietPlanMealId, ClientIp, cancellationToken)).ToActionResult(logger);

    /* --------------------------------- users -------------------------------- */

    [HttpGet("users")]
    public async Task<IActionResult> GetUsers([FromQuery] string? search, [FromQuery] int limit, CancellationToken cancellationToken) =>
        (await consoleService.GetUsersAsync(SessionToken, search, limit, cancellationToken)).ToActionResult(logger);

    /// <summary>
    /// One client's logged data (profile, sessions/sets, meals, bodyweight, hydration,
    /// active plans) over the last <c>days</c> (default 30). Requires users.data.read;
    /// a trainer may only open a user they have assigned a split or diet plan to.
    /// </summary>
    [HttpGet("users/{userId:guid}/overview")]
    public async Task<IActionResult> GetClientOverview(Guid userId, [FromQuery] int days, CancellationToken cancellationToken) =>
        (await consoleService.GetClientOverviewAsync(SessionToken, userId, days <= 0 ? 30 : days, cancellationToken))
            .ToActionResult(logger);

    /// <summary>Super-admin only: replace one user's logs with generated mock history.</summary>
    [HttpPost("users/mock-data")]
    public async Task<IActionResult> SeedUserMockData([FromBody] AdminMockDataRequest request, CancellationToken cancellationToken) =>
        (await consoleService.SeedUserMockDataAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);
}

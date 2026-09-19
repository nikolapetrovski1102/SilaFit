namespace Silen.Common.Authorization;

/// <summary>
/// The canonical permission names the database grants to admin roles.
///
/// These strings are the contract between three places: the rows seeded in
/// database/schema/028_AdminRbac.sql, the policy names the API's endpoints
/// declare, and the permission list the console renders its navigation from.
/// Everything else - which role holds what - is data, not code, which is why
/// there is no "is super admin" flag anywhere in this codebase.
///
/// Format is "&lt;area&gt;.&lt;thing&gt;.&lt;verb&gt;": the area groups a permission in the
/// console's role editor, the verb is the effect. A role can hold read without
/// write, which is how "some operators get read-write, some get read-only" is
/// expressed  - it is a permission set, not a different kind of account.
/// </summary>
public static class AdminPermissions
{
    public const string PlansRead = "content.plans.read";
    public const string PlansWrite = "content.plans.write";

    public const string SplitsRead = "content.splits.read";
    public const string SplitsWrite = "content.splits.write";

    /// <summary>Hand a split to specific app users (the trainer's client list).</summary>
    public const string SplitsAssign = "content.splits.assign";

    /// <summary>Manage every split regardless of owner, including shipped system splits. Without it, an operator only manages the splits they own.</summary>
    public const string SplitsManageAll = "content.splits.manage_all";

    public const string DietPlansRead = "content.diet_plans.read";
    public const string DietPlansWrite = "content.diet_plans.write";

    /// <summary>Hand a diet plan to specific app users (the trainer's client list).</summary>
    public const string DietPlansAssign = "content.diet_plans.assign";

    /// <summary>Manage every diet plan regardless of owner, including shipped system plans. Without it, an operator only manages the plans they own.</summary>
    public const string DietPlansManageAll = "content.diet_plans.manage_all";

    public const string ExercisesRead = "content.exercises.read";
    public const string ExercisesWrite = "content.exercises.write";

    public const string SuggestionsRead = "content.suggestions.read";
    public const string SuggestionsWrite = "content.suggestions.write";

    public const string UsersRead = "users.read";

    /// <summary>
    /// Open one app user's client overview - their onboarding profile plus the
    /// workouts/sets, meals, bodyweight and hydration they actually logged. Held by
    /// trainer, super-admin and analyst; a trainer is still limited to the clients
    /// they have assigned a split or diet plan to (see <see cref="UsersDataReadAll"/>).
    /// </summary>
    public const string UsersDataRead = "users.data.read";

    /// <summary>
    /// View any user's logged data, not just the operator's assigned clients. Held
    /// by super-admin and analyst; deliberately not granted to the shipped trainer
    /// role so a trainer's client list stays the boundary of what they can see.
    /// </summary>
    public const string UsersDataReadAll = "users.data.read_all";

    /// <summary>
    /// Replace one app user's logs with a generated month of mock history so the
    /// monthly overview can be exercised. Destructive (it wipes and regenerates the
    /// user's workouts/meals/hydration/bodyweight), so it ships granted only to
    /// super-admin.
    /// </summary>
    public const string UsersMockData = "users.mock_data";

    /// <summary>Invite, re-role, deactivate and reactivate other console operators.</summary>
    public const string OperatorsManage = "operators.manage";

    /// <summary>Create custom roles and change what they may do.</summary>
    public const string RolesManage = "roles.manage";

    public const string AuditRead = "audit.read";

    /// <summary>
    /// Every permission this build knows about, with the label the console shows
    /// and the area it groups under. The API hands this to the role editor, so the
    /// console never has to keep its own copy of the catalog (and can't drift).
    /// </summary>
    public static readonly IReadOnlyList<AdminPermissionDescriptor> Catalog =
    [
        new(PlansRead, "Plans", "View subscription plans", "Pricing tiers, prices and feature lists."),
        new(PlansWrite, "Plans", "Edit subscription plans", "Create, change and retire plans and their features."),
        new(SplitsRead, "Splits", "View workout splits", "The split library, its days and exercise prescriptions."),
        new(SplitsWrite, "Splits", "Edit workout splits", "Create and change splits, days and prescriptions."),
        new(SplitsAssign, "Splits", "Assign splits to users", "Hand a split to specific app users and set it as their active program."),
        new(SplitsManageAll, "Splits", "Manage every split", "Change splits owned by other trainers, including the shipped system splits."),
        new(DietPlansRead, "Diet plans", "View diet plans", "The diet plan library, its days and meal slots."),
        new(DietPlansWrite, "Diet plans", "Edit diet plans", "Create and change plans, days and meal slots."),
        new(DietPlansAssign, "Diet plans", "Assign diet plans to users", "Hand a plan to specific app users and set it as their active plan."),
        new(DietPlansManageAll, "Diet plans", "Manage every diet plan", "Change plans owned by other trainers, including the shipped system plans."),
        new(ExercisesRead, "Exercises", "View exercises", "The exercise library and where each exercise is used."),
        new(ExercisesWrite, "Exercises", "Edit exercises", "Add, change and remove exercises."),
        new(SuggestionsRead, "Meal suggestions", "View meal suggestions", "The month-tagged suggestion catalog."),
        new(SuggestionsWrite, "Meal suggestions", "Edit meal suggestions", "Add, change and remove suggestions."),
        new(UsersRead, "Users", "View app users", "Account tier, join date and current subscription - never anyone's logs or body data."),
        new(UsersDataRead, "Users", "View client logs", "One user's onboarding profile and the workouts/sets, meals, bodyweight and hydration they logged."),
        new(UsersDataReadAll, "Users", "View any client's logs", "Open a user who is not one of your assigned clients."),
        new(UsersMockData, "Users", "Generate mock data", "Replace one user's logs with a generated month of workouts, meals, hydration and bodyweight for testing."),
        new(OperatorsManage, "Operators", "Manage operators", "Move operators between roles and deactivate them."),
        new(RolesManage, "Roles", "Manage custom roles", "Create custom roles and choose what each may do."),
        new(AuditRead, "Audit", "Read the audit log", "Every change an operator has made, with who, what and from where.")
    ];

    private static readonly HashSet<string> Known = [.. Catalog.Select(item => item.Permission)];

    public static bool IsKnown(string? permission) =>
        !string.IsNullOrWhiteSpace(permission) && Known.Contains(permission);
}

/// <summary>One entry in the permission catalog: the name plus how to present it.</summary>
public sealed record AdminPermissionDescriptor(string Permission, string Group, string Label, string Description);

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

    public const string ExercisesRead = "content.exercises.read";
    public const string ExercisesWrite = "content.exercises.write";

    public const string SuggestionsRead = "content.suggestions.read";
    public const string SuggestionsWrite = "content.suggestions.write";

    public const string UsersRead = "users.read";

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
        new(ExercisesRead, "Exercises", "View exercises", "The exercise library and where each exercise is used."),
        new(ExercisesWrite, "Exercises", "Edit exercises", "Add, change and remove exercises."),
        new(SuggestionsRead, "Meal suggestions", "View meal suggestions", "The month-tagged suggestion catalog."),
        new(SuggestionsWrite, "Meal suggestions", "Edit meal suggestions", "Add, change and remove suggestions."),
        new(UsersRead, "Users", "View app users", "Account tier, join date and current subscription - never anyone's logs or body data."),
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

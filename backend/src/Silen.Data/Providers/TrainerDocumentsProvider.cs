using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="ITrainerDocumentsProvider"/>
public sealed class TrainerDocumentsProvider(ISqlExecutor sqlExecutor) : ITrainerDocumentsProvider
{
    public Task<List<TrainerDocumentModel>> GetForTargetAsync(string kind, Guid targetId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_TrainerDocuments_GetForTarget",
            [SqlParameterBuilder.Create("@Kind", kind), SqlParameterBuilder.Create("@TargetId", targetId)],
            reader => SqlResultSetReader.ReadListAsync(reader, TrainerDocumentRowMapper.MapDocument, cancellationToken),
            cancellationToken);

    public Task<TrainerDocumentFileModel?> GetAsync(Guid documentId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_TrainerDocument_Get",
            [SqlParameterBuilder.Create("@DocumentId", documentId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, TrainerDocumentRowMapper.MapDocumentFile, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> CreateAsync(
        string kind, Guid targetId, string title, string originalFileName, string storedFileName, long sizeBytes,
        bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_TrainerDocument_Create",
            [
                SqlParameterBuilder.Create("@Kind", kind),
                SqlParameterBuilder.Create("@TargetId", targetId),
                SqlParameterBuilder.Create("@Title", title),
                SqlParameterBuilder.Create("@OriginalFileName", originalFileName),
                SqlParameterBuilder.Create("@StoredFileName", storedFileName),
                SqlParameterBuilder.Create("@SizeBytes", sizeBytes),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteAsync(Guid documentId, bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_TrainerDocument_Delete",
            [
                SqlParameterBuilder.Create("@DocumentId", documentId),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<TrainerDocumentGrantModel>> GetGrantsAsync(Guid documentId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_TrainerDocumentGrants_GetForDocument",
            [SqlParameterBuilder.Create("@DocumentId", documentId)],
            reader => SqlResultSetReader.ReadListAsync(reader, TrainerDocumentRowMapper.MapGrant, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> AssignAsync(
        Guid documentId, Guid userId, string token, bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_TrainerDocumentGrant_Assign",
            [
                SqlParameterBuilder.Create("@DocumentId", documentId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Token", token),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> RevokeAsync(Guid grantId, bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_TrainerDocumentGrant_Revoke",
            [
                SqlParameterBuilder.Create("@GrantId", grantId),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<TrainerDocumentAccessModel?> GetByTokenAsync(string token, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_TrainerDocument_GetByToken",
            [SqlParameterBuilder.Create("@Token", token)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, TrainerDocumentRowMapper.MapAccess, cancellationToken),
            cancellationToken);

    public Task RecordOpenAsync(Guid grantId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_TrainerDocumentGrant_RecordOpen",
            [SqlParameterBuilder.Create("@GrantId", grantId)],
            cancellationToken);

    public Task<List<UserTrainerDocumentModel>> GetForUserAsync(Guid userId, string kind, Guid targetId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_TrainerDocuments_GetForUser",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Kind", kind),
                SqlParameterBuilder.Create("@TargetId", targetId)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, TrainerDocumentRowMapper.MapUserDocument, cancellationToken),
            cancellationToken);

    public Task<string?> IssueTicketAsync(Guid userId, Guid grantId, byte[] ticketHash, DateTime expiresAtUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_TrainerDocumentGrant_IssueTicket",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@GrantId", grantId),
                SqlParameterBuilder.Create("@TicketHash", ticketHash),
                SqlParameterBuilder.Create("@TicketExpiresAtUtc", expiresAtUtc)
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? TrainerDocumentRowMapper.MapToken(reader) : null,
            cancellationToken);

    public Task<string?> IssueEmailLinkAsync(Guid grantId, byte[] linkHash, DateTime expiresAtUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_TrainerDocumentGrant_IssueEmailLink",
            [
                SqlParameterBuilder.Create("@GrantId", grantId),
                SqlParameterBuilder.Create("@LinkHash", linkHash),
                SqlParameterBuilder.Create("@LinkExpiresAtUtc", expiresAtUtc)
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? TrainerDocumentRowMapper.MapToken(reader) : null,
            cancellationToken);

    public Task<TrainerAssignmentNotifyContextModel?> GetAssignmentNotifyContextAsync(
        Guid userId, string kind, Guid targetId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_TrainerAssignment_GetNotifyContext",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Kind", kind),
                SqlParameterBuilder.Create("@TargetId", targetId)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, TrainerDocumentRowMapper.MapNotifyContext, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> ImportSplitAsync(
        string name, string level, string? description, int durationDays, string daysJson,
        AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Split_ImportGenerated",
            [
                SqlParameterBuilder.Create("@Name", name),
                SqlParameterBuilder.Create("@Level", level),
                SqlParameterBuilder.Create("@Description", description),
                SqlParameterBuilder.Create("@DurationDays", (short)durationDays),
                SqlParameterBuilder.Create("@DaysJson", daysJson),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> ImportDietPlanAsync(
        string name, string? description, int durationDays, string daysJson,
        AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlan_ImportGenerated",
            [
                SqlParameterBuilder.Create("@Name", name),
                SqlParameterBuilder.Create("@Description", description),
                SqlParameterBuilder.Create("@DurationDays", (short)durationDays),
                SqlParameterBuilder.Create("@DaysJson", daysJson),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);
}

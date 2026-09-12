using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Turns the Outcome row an admin write procedure returns into either a success
/// payload or the exception the API should turn into a status code.
///
/// The business rules live in SQL on purpose (only the procedure can check "is
/// this exercise still used" and delete in one transaction), so the service must
/// not second-guess them - it translates. The Detail sentence comes straight back
/// as the user-facing message: those strings are written for operators, and they
/// describe state the caller is already allowed to see.
/// </summary>
public static class AdminMutationOutcomeMapper
{
    public static AdminWriteResultDto Resolve(AdminMutationResultModel mutation, string successMessage) =>
        mutation.Result switch
        {
            AdminWriteOutcome.Success => new AdminWriteResultDto
            {
                Id = mutation.EntityId,
                Message = successMessage
            },
            AdminWriteOutcome.NotFound => throw new NotFoundException(
                mutation.Detail ?? "The admin write reported a missing row.",
                mutation.Detail),
            AdminWriteOutcome.Conflict => throw new ConflictException(
                mutation.Detail ?? "The admin write was refused by the database.",
                mutation.Detail),
            _ => throw new ValidationException(
                mutation.Detail ?? "The admin write was rejected.",
                mutation.Detail)
        };
}

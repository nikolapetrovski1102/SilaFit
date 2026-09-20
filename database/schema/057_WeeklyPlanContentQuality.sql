USE SilenDb;
GO

-- Existing installations already have these prompt rows, so reinforce the
-- quality requirements here as well as in the runtime prompt assembled by
-- WeeklyPlanGenerationService.
UPDATE dbo.AiPromptTemplates
SET
    SystemPrompt = SystemPrompt +
        N' Every non-rest training day must contain 5 to 8 unique exercises: compound movements first, ' +
        N'then accessories that complete the day''s muscle coverage. Rest days must contain no exercises.',
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE TemplateKey = N'WeeklySplitGeneration'
  AND SystemPrompt NOT LIKE N'%5 to 8 unique exercises%';
GO

UPDATE dbo.AiPromptTemplates
SET
    SystemPrompt = SystemPrompt +
        N' Review each meal''s compact ingredient preview as well as its macros. Prefer a clear whole-food ' +
        N'protein, useful produce or fiber, and avoid a repetitive or highly processed week.',
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE TemplateKey = N'WeeklyDietGeneration'
  AND SystemPrompt NOT LIKE N'%compact ingredient preview%';
GO

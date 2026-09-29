using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

/// <summary>Posted by the website's support page (website/support.html). Anonymous -
/// the visitor may not have an account at all, or may be locked out of it.</summary>
public sealed class SupportContactRequest
{
    [Required(ErrorMessage = "Please enter your name.")]
    [StringLength(100, MinimumLength = 1, ErrorMessage = "Please keep your name under 100 characters.")]
    public string Name { get; set; } = string.Empty;

    [Required(ErrorMessage = "Please enter your email address.")]
    [EmailAddress(ErrorMessage = "Please enter a valid email address.")]
    [StringLength(256, ErrorMessage = "Please enter a valid email address.")]
    public string Email { get; set; } = string.Empty;

    /// <summary>One of <c>SupportService.Topics</c>' keys.</summary>
    [Required(ErrorMessage = "Please choose a topic.")]
    [StringLength(32)]
    public string Topic { get; set; } = string.Empty;

    [Required(ErrorMessage = "Please describe what happened.")]
    [StringLength(5000, MinimumLength = 10, ErrorMessage = "Please write between 10 and 5,000 characters.")]
    public string Message { get; set; } = string.Empty;

    /// <summary>Honeypot. Hidden from people by the form's CSS, so only bots fill it in.</summary>
    [StringLength(500)]
    public string? Website { get; set; }
}

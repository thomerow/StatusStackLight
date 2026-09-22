using Microsoft.AspNetCore.Identity;
using StatusStackLight.Relay.Data;

namespace StatusStackLight.Relay.Services;

/// <summary>
/// The single admin password. It is set on the server with <c>set-password</c>, never over
/// the web: an admin interface on the internet that lets the first visitor choose the
/// password is an open door until someone gets there first.
/// </summary>
public sealed class AdminPassword(ConfigStore store)
{
    public const int MinLength = 10;

    private static readonly PasswordHasher<object> Hasher = new();
    private static readonly object User = new();

    public async Task<bool> IsSetAsync() => await store.GetPasswordHashAsync() is not null;

    public async Task<bool> VerifyAsync(string password)
    {
        var hash = await store.GetPasswordHashAsync();
        if (hash is null || string.IsNullOrEmpty(password)) return false;
        return Hasher.VerifyHashedPassword(User, hash, password) != PasswordVerificationResult.Failed;
    }

    public Task SetAsync(string password) => store.SetPasswordHashAsync(Hasher.HashPassword(User, password));

    /// <summary>
    /// The <c>set-password</c> command. Reads the password twice from the console without echo,
    /// or once from stdin when it is redirected (for scripts: <c>echo ... | relay set-password</c>).
    /// </summary>
    public async Task<int> RunCommandAsync()
    {
        string? password;
        if (Console.IsInputRedirected) {
            password = Console.In.ReadLine();
        } else {
            password = ReadHidden("New admin password: ");
            if (password != ReadHidden("Repeat: ")) {
                Console.Error.WriteLine("The passwords do not match - nothing changed.");
                return 1;
            }
        }

        if (password is null || password.Length < MinLength) {
            Console.Error.WriteLine($"The password must have at least {MinLength} characters - nothing changed.");
            return 1;
        }

        await SetAsync(password);
        Console.WriteLine("Admin password set.");
        return 0;
    }

    private static string ReadHidden(string prompt)
    {
        Console.Write(prompt);
        var chars = new List<char>();
        while (true) {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter) break;
            if (key.Key == ConsoleKey.Backspace) {
                if (chars.Count > 0) chars.RemoveAt(chars.Count - 1);
            } else if (!char.IsControl(key.KeyChar)) {
                chars.Add(key.KeyChar);
            }
        }
        Console.WriteLine();
        return new string([.. chars]);
    }
}

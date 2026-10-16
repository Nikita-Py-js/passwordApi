using System;
using System.Configuration;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Web;
using System.Web.Script.Serialization;

public static class SecretStore
{
    private static string SecretsDir
    {
        get
        {
            string dir = HttpContext.Current.Server.MapPath("~/App_Data/secrets");
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            return dir;
        }
    }

    private static byte[] Key
    {
        get
        {
            string b64 = ConfigurationManager.AppSettings["EncryptionKey"];
            if (string.IsNullOrEmpty(b64))
                throw new InvalidOperationException("EncryptionKey не задан в Web.config");
            byte[] key = Convert.FromBase64String(b64);
            if (key.Length != 32)
                throw new InvalidOperationException("EncryptionKey должен быть 32 байта в base64.");
            return key;
        }
    }

    public static string Create(string plaintext, TimeSpan ttl)
    {
        string id = Guid.NewGuid().ToString("N");
        var payload = new SecretPayload
        {
            ExpiresUnix = ToUnix(DateTime.UtcNow.Add(ttl)),
            Data = Encrypt(plaintext)
        };
        string json = new JavaScriptSerializer().Serialize(payload);

        string path = Path.Combine(SecretsDir, id + ".secret");
        string tmp = path + ".tmp";
        File.WriteAllText(tmp, json, Encoding.UTF8);
        File.Move(tmp, path);
        return id;
    }

    // Атомарно забирает секрет. Возвращает null, если его нет, он истёк или уже был забран.
    public static string Take(string id)
    {
        if (!IsValidId(id)) return null;

        string path = Path.Combine(SecretsDir, id + ".secret");
        if (!File.Exists(path)) return null;

        // Захватываем файл: если кто-то параллельно уже сделал Move — упадёт.
        string claimed = Path.Combine(SecretsDir, id + ".claimed_" + Guid.NewGuid().ToString("N"));
        try
        {
            File.Move(path, claimed);
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }

        try
        {
            string json = File.ReadAllText(claimed, Encoding.UTF8);
            var payload = new JavaScriptSerializer().Deserialize<SecretPayload>(json);
            if (payload == null) return null;
            if (payload.ExpiresUnix < ToUnix(DateTime.UtcNow)) return null;
            return Decrypt(payload.Data);
        }
        catch
        {
            return null;
        }
        finally
        {
            try { File.Delete(claimed); } catch { /* ignore */ }
        }
    }

    // Удаляет просроченные/подвисшие файлы. Вызывается лениво из Create.
    public static void CleanupExpired()
    {
        long now = ToUnix(DateTime.UtcNow);
        foreach (string f in Directory.GetFiles(SecretsDir, "*.secret"))
        {
            try
            {
                string json = File.ReadAllText(f, Encoding.UTF8);
                var p = new JavaScriptSerializer().Deserialize<SecretPayload>(json);
                if (p == null || p.ExpiresUnix < now) File.Delete(f);
            }
            catch { /* ignore */ }
        }
        // подчищаем подвисшие claimed-файлы старше суток
        foreach (string f in Directory.GetFiles(SecretsDir, "*.claimed_*"))
        {
            try
            {
                if (File.GetLastWriteTimeUtc(f) < DateTime.UtcNow.AddDays(-1))
                    File.Delete(f);
            }
            catch { /* ignore */ }
        }
    }

    private static bool IsValidId(string id)
    {
        if (string.IsNullOrEmpty(id) || id.Length != 32) return false;
        for (int i = 0; i < id.Length; i++)
            if (!Uri.IsHexDigit(id[i])) return false;
        return true;
    }

    private static long ToUnix(DateTime utc)
    {
        return (long)(utc - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
    }

    private static string Encrypt(string plain)
    {
        using (var aes = Aes.Create())
        {
            aes.Key = Key;
            aes.GenerateIV();
            byte[] plainBytes = Encoding.UTF8.GetBytes(plain);
            using (var enc = aes.CreateEncryptor())
            {
                byte[] cipher = enc.TransformFinalBlock(plainBytes, 0, plainBytes.Length);
                byte[] result = new byte[aes.IV.Length + cipher.Length];
                Buffer.BlockCopy(aes.IV, 0, result, 0, aes.IV.Length);
                Buffer.BlockCopy(cipher, 0, result, aes.IV.Length, cipher.Length);
                return Convert.ToBase64String(result);
            }
        }
    }

    private static string Decrypt(string b64)
    {
        byte[] data = Convert.FromBase64String(b64);
        using (var aes = Aes.Create())
        {
            aes.Key = Key;
            byte[] iv = new byte[16];
            Buffer.BlockCopy(data, 0, iv, 0, 16);
            aes.IV = iv;
            using (var dec = aes.CreateDecryptor())
            {
                byte[] plain = dec.TransformFinalBlock(data, 16, data.Length - 16);
                return Encoding.UTF8.GetString(plain);
            }
        }
    }

    public class SecretPayload
    {
        public long ExpiresUnix { get; set; }
        public string Data { get; set; }
    }
}
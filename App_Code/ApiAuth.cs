using System;
using System.Configuration;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web;

public static class ApiAuth
{
    public static bool IsAuthorized(HttpContext ctx, out string error)
    {
        error = null;

        // 1. IP-фильтр (если задан)
        string allowed = ConfigurationManager.AppSettings["ApiAllowedIps"];
        if (!string.IsNullOrWhiteSpace(allowed))
        {
            string ip = ctx.Request.UserHostAddress ?? "";
            bool ok = allowed.Split(',')
                .Select(s => s.Trim())
                .Any(s => string.Equals(s, ip, StringComparison.OrdinalIgnoreCase));
            if (!ok)
            {
                error = "IP не разрешён";
                return false;
            }
        }

        // 2. Ключ
        string expected = ConfigurationManager.AppSettings["ApiKey"];
        if (string.IsNullOrEmpty(expected))
        {
            error = "ApiKey не задан в Web.config";
            return false;
        }

        string provided = ctx.Request.Headers["X-Api-Key"];
        if (string.IsNullOrEmpty(provided))
            provided = ctx.Request.Form["api_key"]; // запасной вариант

        if (string.IsNullOrEmpty(provided) || !FixedTimeEquals(provided, expected))
        {
            error = "Неверный API-ключ";
            return false;
        }
        return true;
    }

    // Постоянное по времени сравнение — чтобы не текла длина совпадающего префикса
    private static bool FixedTimeEquals(string a, string b)
    {
        byte[] ba = Encoding.UTF8.GetBytes(a);
        byte[] bb = Encoding.UTF8.GetBytes(b);
        if (ba.Length != bb.Length) return false;
        int diff = 0;
        for (int i = 0; i < ba.Length; i++) diff |= ba[i] ^ bb[i];
        return diff == 0;
    }
}
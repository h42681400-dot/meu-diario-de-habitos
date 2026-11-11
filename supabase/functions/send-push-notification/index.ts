/// <reference lib="deno.ns" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "").replace(/-----END PRIVATE KEY-----/g, "").replace(/\s/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function getGoogleAccessToken(serviceAccount: { client_email: string; private_key: string; token_uri?: string }) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri || "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = header + "." + claim;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const assertion = unsigned + "." + base64url(signature);
  const response = await fetch(serviceAccount.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || !result.access_token) throw new Error("Falha ao obter token OAuth do Google: " + JSON.stringify(result));
  return result.access_token as string;
}

const descriptions: Record<string, string> = {
  like: "curtiu sua publicação. 🤍",
  comment: "comentou na sua publicação. 💬",
  repost: "repostou sua publicação. 🔁",
  message: "enviou uma mensagem. 💌",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const authorization = req.headers.get("authorization") || "";
  if (!expectedSecret || authorization !== "Bearer " + expectedSecret) {
    return new Response("Unauthorized", { status: 401, headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const notification = payload?.record ?? payload?.data?.record ?? payload;
    const { user_id, actor_id, type, post_id } = notification ?? {};
    if (!user_id || !type || !descriptions[type]) {
      return Response.json({ ignored: true, reason: "Tipo de notificação não suportado" }, { headers: corsHeaders });
    }
    if (actor_id && actor_id === user_id) {
      return Response.json({ ignored: true, reason: "Notificação própria" }, { headers: corsHeaders });
    }

    const serviceAccountRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceAccountRaw || !supabaseUrl || !serviceRoleKey) throw new Error("Secrets obrigatórios ausentes.");
    const serviceAccount = JSON.parse(serviceAccountRaw);
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const [{ data: tokens, error: tokenError }, { data: actor }] = await Promise.all([
      admin.from("device_push_tokens").select("token").eq("user_id", user_id).eq("platform", "android"),
      actor_id
        ? admin.from("user_profiles").select("full_name,username").eq("user_id", actor_id).maybeSingle()
        : Promise.resolve({ data: null }),
    ]);
    if (tokenError) throw tokenError;
    if (!tokens?.length) return Response.json({ sent: 0, reason: "Usuário sem dispositivo registrado" }, { headers: corsHeaders });

    const actorName = actor?.full_name || (actor?.username ? "@" + actor.username : "Alguém");
    const title = type === "message" ? actorName : "Cottontail 🐰";
    const body = actorName + " " + descriptions[type];
    const accessToken = await getGoogleAccessToken(serviceAccount);
    const projectId = serviceAccount.project_id;
    if (!projectId) throw new Error("project_id ausente no JSON da conta de serviço.");

    const route = type === "message" ? "messages" : "notifications";
    const results = await Promise.all((tokens || []).map(async ({ token }: { token: string }) => {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: "POST",
        headers: {
          Authorization: "Bearer " + accessToken,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: {
              type: String(type),
              actor_id: String(actor_id || ""),
              post_id: String(post_id || ""),
              route,
            },
            android: {
              priority: "HIGH",
              notification: {
                channel_id: "cottontail_notifications",
                sound: "default",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
            },
          },
        }),
      });
      const result = await response.json().catch(() => ({}));
      return { ok: response.ok, status: response.status, result };
    }));
    const sent = results.filter((r) => r.ok).length;
    return Response.json({ sent, total: results.length, results }, { headers: corsHeaders });
  } catch (error) {
    console.error("send-push-notification:", error);
    return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500, headers: corsHeaders });
  }
});

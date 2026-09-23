// Disparo de activaciones hacia WhatsApp/ManyChat — pivot a tratamiento de
// leads (Fase 4 del roadmap, en progreso).
// Ref: specs/2026-09-23-pivot-leads-whatsapp.md,
//      specs/2026-09-18-utm-manychat-y-disparo-campanas.md, db/006_activaciones_whatsapp.sql
//
// Por qué "aplicar tag" y no "enviar mensaje libre": enviar contenido a un
// segmento por API choca con las ventanas de mensajería de WhatsApp Business
// (24hs desde el último mensaje del usuario, o plantilla pre-aprobada por
// Meta fuera de eso) y rompería la regla de que Taquión administra los
// flujos del bot (specs/006). Esta función solo decide A QUIÉN taggear —
// el mensaje real lo dispara un flow de ManyChat ya configurado para
// reaccionar a ese tag.
//
// Auth: a diferencia de api-publica (key propia por consumidor externo),
// esto lo llama el panel ya logueado — se valida el JWT de la sesión de
// Supabase y se exige admin_taquion (misma función es_admin() que usa RLS
// en el resto del esquema).
//
// Dependencia externa sin resolver en este PR: MANYCHAT_API_KEY como secret
// de Supabase (`supabase secrets set MANYCHAT_API_KEY=...`) y al menos un
// contacto con manychat_subscriber_id poblado. Sin eso, la función responde
// 501/422 explícito en vez de fallar en silencio — ver README "Qué falta".
//
// Deploy: `supabase functions deploy activacion-manychat`.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MANYCHAT_API_KEY = Deno.env.get("MANYCHAT_API_KEY");

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface Filtro {
  arquetipo_id?: string;
  corredor_localidad?: string;
  estado_identificacion?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Método no soportado, usar POST" }, 405);
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return json({ error: "Falta el header Authorization (sesión de admin_taquion)" }, 401);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user) {
    return json({ error: "Sesión inválida o expirada" }, 401);
  }

  const { data: esAdmin, error: errEsAdmin } = await admin
    .schema("crm_comunidades")
    .rpc("es_admin", { p_uid: userData.user.id });
  if (errEsAdmin) return json({ error: errEsAdmin.message }, 500);
  if (!esAdmin) {
    return json({ error: "Solo admin_taquion puede disparar activaciones" }, 403);
  }

  const body = await req.json().catch(() => null);
  const activacionId: string | undefined = body?.activacion_id;
  const filtro: Filtro = body?.filtro ?? {};
  if (!activacionId) return json({ error: "Falta activacion_id" }, 400);

  const { data: activacion, error: errActivacion } = await admin
    .schema("crm_comunidades")
    .from("activacion")
    .select("id, comunidad_id, nombre")
    .eq("id", activacionId)
    .maybeSingle();
  if (errActivacion) return json({ error: errActivacion.message }, 500);
  if (!activacion) return json({ error: "Activación no encontrada" }, 404);

  const tagManychat = `activacion_${activacion.id}`;

  // Resuelve el segmento: solo contactos de la misma comunidad ya vinculados
  // a un subscriber real de ManyChat (nunca cruza comunidades).
  let query = admin
    .schema("crm_comunidades")
    .from("contacto")
    .select("id, manychat_subscriber_id")
    .eq("comunidad_id", activacion.comunidad_id)
    .not("manychat_subscriber_id", "is", null);
  if (filtro.arquetipo_id) query = query.eq("arquetipo_id", filtro.arquetipo_id);
  if (filtro.corredor_localidad) query = query.eq("corredor_localidad", filtro.corredor_localidad);
  if (filtro.estado_identificacion) query = query.eq("estado_identificacion", filtro.estado_identificacion);

  const { data: contactos, error: errContactos } = await query;
  if (errContactos) return json({ error: errContactos.message }, 500);

  async function registrarDisparo(estado: "ok" | "parcial" | "error", cantidad: number, respuestaApi: unknown) {
    return admin.schema("crm_comunidades").from("activacion_disparo").insert({
      activacion_id: activacionId,
      filtro_usado: filtro,
      cantidad_contactos: cantidad,
      tag_manychat: tagManychat,
      estado,
      respuesta_api: respuestaApi,
      disparado_por: userData.user.email,
    }).select().maybeSingle();
  }

  if (!MANYCHAT_API_KEY) {
    const { data: disparo } = await registrarDisparo("error", contactos?.length ?? 0, {
      error: "MANYCHAT_API_KEY no está configurada como secret de Supabase",
    });
    return json({ error: "MANYCHAT_API_KEY no configurada — ver README, sección de la Fase 4", data: disparo }, 501);
  }

  if (!contactos?.length) {
    const { data: disparo } = await registrarDisparo("error", 0, {
      error: "Ningún contacto con manychat_subscriber_id en esta comunidad todavía",
    });
    return json({ error: "Sin contactos vinculados a ManyChat todavía (contacto.manychat_subscriber_id vacío)", data: disparo }, 422);
  }

  const resultados = await Promise.all(contactos.map(async (c) => {
    try {
      const res = await fetch("https://api.manychat.com/fb/subscriber/addTagByName", {
        method: "POST",
        headers: { Authorization: `Bearer ${MANYCHAT_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ subscriber_id: c.manychat_subscriber_id, tag_name: tagManychat }),
      });
      return { contacto_id: c.id, ok: res.ok, status: res.status };
    } catch (e) {
      return { contacto_id: c.id, ok: false, error: String(e) };
    }
  }));

  const okCount = resultados.filter((r) => r.ok).length;
  const estadoFinal: "ok" | "parcial" | "error" =
    okCount === resultados.length ? "ok" : okCount > 0 ? "parcial" : "error";

  const { data: disparo, error: errDisparo } = await registrarDisparo(estadoFinal, contactos.length, { resultados });
  if (errDisparo) return json({ error: errDisparo.message }, 500);

  return json({ data: disparo });
});

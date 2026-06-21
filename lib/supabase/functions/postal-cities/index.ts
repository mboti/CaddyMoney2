// supabase/functions/postal-cities/index.ts

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type RequestBody = {
  countryCode?: string; // e.g. "fr"
  postalCode?: string; // e.g. "70000"
};

type ResponseBody = {
  cities: string[];
  source: "zippopotam";
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const contentType = req.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().includes("application/json")) {
      return new Response(JSON.stringify({ error: "Expected application/json" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const body = (await req.json()) as RequestBody;
    const countryCode = (body.countryCode ?? "").trim().toLowerCase();
    const postalCode = (body.postalCode ?? "").trim();

    if (!countryCode || !postalCode) {
      return new Response(JSON.stringify({ error: "countryCode and postalCode are required" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const upstreamUrl = `https://api.zippopotam.us/${encodeURIComponent(countryCode)}/${encodeURIComponent(postalCode)}`;

    const upstream = await fetch(upstreamUrl, {
      method: "GET",
      headers: {
        "accept": "application/json",
        // Some upstreams behave better with a UA.
        "user-agent": "supabase-edge-postal-cities/1.0",
      },
    });

    if (upstream.status === 404) {
      const resp: ResponseBody = { cities: [], source: "zippopotam" };
      return new Response(JSON.stringify(resp), {
        status: 200,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    if (!upstream.ok) {
      return new Response(JSON.stringify({ error: `Upstream error: ${upstream.status}` }), {
        status: 502,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const json = await upstream.json();
    const places = Array.isArray(json?.places) ? json.places : [];
    const citiesSet = new Set<string>();
    for (const p of places) {
      const name = typeof p?.["place name"] === "string" ? p["place name"].trim() : "";
      if (name) citiesSet.add(name);
    }

    const resp: ResponseBody = { cities: Array.from(citiesSet).sort(), source: "zippopotam" };
    return new Response(JSON.stringify(resp), {
      status: 200,
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `Unhandled: ${String(e)}` }), {
      status: 500,
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  }
});

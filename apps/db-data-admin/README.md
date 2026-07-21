# DB Data Admin frontend

Administrator application for the shared Customer, Vendor, Licensor, and Property hubs.
The authoritative product and delivery requirements are in [`../../DB_Data_Admin.md`](../../DB_Data_Admin.md).

## Local preview shell

1. Copy `.env.example` to `.env.local`.
2. Put only the preview project's public Supabase URL/anon key in that ignored file.
3. Run `npm install`, then `npm run dev`.

Never use production credentials for local development. Microsoft login uses Supabase Auth's
existing Azure provider and the exact `VITE_AUTH_REDIRECT_URL` allowlisted for the environment.
Production access stays disabled until the preview delivery gates in the specification pass.

Deployed containers receive `DB_DATA_ADMIN_SUPABASE_URL`,
`DB_DATA_ADMIN_SUPABASE_ANON_KEY`, and `DB_DATA_ADMIN_AUTH_REDIRECT_URL` from Coolify.
They are rendered at container startup through `/config.js`; GitHub builds one immutable image
without baking environment-specific configuration into it.

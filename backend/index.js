// index.js
const { ulid } = require('ulid');
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

app.get('/api/manufacturers-with-aliases', async (req, res) => {
  const search = req.query.search || '';
  const page = parseInt(req.query.page || '1');
  const limit = 20;
  const offset = (page - 1) * limit;

  const client = await pool.connect();

  try {
    const result = await client.query(
      `SELECT
  m.id AS manufacturer_id,
  m.name AS manufacturer_name,
  EXISTS (
    SELECT 1 FROM supplier_manufacturers sm
    WHERE sm.manufacturer_id = m.id AND LOWER(sm.name) = LOWER(m.name)
  ) AS has_exact_match,
  JSON_AGG(
    JSON_BUILD_OBJECT('id', sm.id, 'name', sm.name)
  ) FILTER (WHERE LOWER(sm.name) <> LOWER(m.name)) AS aliases
  FROM manufacturers m
  LEFT JOIN supplier_manufacturers sm ON sm.manufacturer_id = m.id
  WHERE $1 = ''
  OR LOWER(m.name) LIKE '%' || LOWER($1) || '%'
  OR EXISTS (
    SELECT 1 FROM supplier_manufacturers sm2
    WHERE sm2.manufacturer_id = m.id
      AND LOWER(sm2.name) <> LOWER(m.name)
      AND LOWER(sm2.name) LIKE '%' || LOWER($1) || '%'
  )
  GROUP BY m.id, m.name
  ORDER BY m.name
  LIMIT $2 OFFSET $3
                    `,
      [search, limit, offset]
    );

    const data = result.rows.map(row => ({
      id: row.manufacturer_id,
      name: row.manufacturer_name,
      has_exact_match: row.has_exact_match, // 👈 EZ HIÁNYZOTT!
      aliases: row.aliases ?? [],
    }));
    

    res.json(data);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Database query failed' });
  } finally {
    client.release();
  }
});


app.get('/api/unmatched-supplier-manufacturers', async (req, res) => {
  const search = req.query.search || '';
  const page = parseInt(req.query.page || '1');
  const limit = 20;
  const offset = (page - 1) * limit;

  const client = await pool.connect();

  try {
    const result = await client.query(
      `SELECT id, name
       FROM supplier_manufacturers
       WHERE manufacturer_id IS NULL
         AND ($1 = '' OR LOWER(name) LIKE '%' || LOWER($1) || '%')
       ORDER BY name
       LIMIT $2 OFFSET $3`,
      [search, limit, offset]
    );

    const data = result.rows.map(row => ({
      id: row.id,
      name: row.name,
    }));

    res.json(data);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Database query failed' });
  } finally {
    client.release();
  }
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});

app.post('/api/create-and-link-manufacturer', async (req, res) => {
  const { supplier_manufacturer_id, name } = req.body;

  if (!supplier_manufacturer_id || !name) {
    return res.status(400).json({ error: 'Hiányzó mezők: supplier_manufacturer_id vagy name' });
  }

  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')       // Szóköz, ékezet, stb. helyett kötőjel
    .replace(/^-+|-+$/g, '');           // Kezdő/vég kötőjelek eltávolítása

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // 1. Új saját gyártó beszúrása
    const newId = ulid();

  const insertManufacturerResult = await client.query(
   `INSERT INTO manufacturers (id, name, slug)
    VALUES ($1, $2, $3)
    RETURNING id`,
   [newId, name, slug]
  );


    const newManufacturerId = insertManufacturerResult.rows[0].id;

    // 2. supplier_manufacturer frissítése
    await client.query(
      `UPDATE supplier_manufacturers
       SET manufacturer_id = $1
       WHERE id = $2`,
      [newManufacturerId, supplier_manufacturer_id]
    );

    await client.query('COMMIT');
    res.json({ success: true, manufacturer_id: newManufacturerId });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Hiba a gyártó létrehozásánál:', error);
    res.status(500).json({ error: 'Hiba a gyártó létrehozásánál' });
  } finally {
    client.release();
  }
});

app.post('/api/inactive-supplier-manufacturer', async (req, res) => {
  const { supplier_manufacturer_id, name } = req.body;

  if (!supplier_manufacturer_id || !name) {
    return res.status(400).json({ error: 'Hiányzó mezők: supplier_manufacturer_id vagy name' });
  }

    const client = await pool.connect();

  try {
    await client.query('BEGIN');

    await client.query(
      `UPDATE supplier_manufacturers
       SET is_active = 0
       WHERE id = $1`,
      [supplier_manufacturer_id]
    );

    await client.query('COMMIT');
    res.json({ success: true, manufacturer_id: newManufacturerId });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Hiba a gyártó inkativálásánál:', error);
    res.status(500).json({ error: 'Hiba a gyártó inkativálásánál' });
  } finally {
    client.release();
  }
});

app.post('/api/pair-manufacturer', async (req, res) => {
  const { supplier_manufacturer_id, manufacturer_id } = req.body;

  if (!supplier_manufacturer_id || !manufacturer_id) {
    return res.status(400).json({ error: 'Hiányzó mezők' });
  }

  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE supplier_manufacturers
       SET manufacturer_id = $1
       WHERE id = $2`,
      [manufacturer_id, supplier_manufacturer_id]
    );
    res.json({ success: true });
  } catch (error) {
    console.error('Hiba a párosításnál:', error);
    res.status(500).json({ error: 'Párosítás hiba' });
  } finally {
    client.release();
  }
});

app.post('/api/unpair-alias', async (req, res) => {
  const { supplier_manufacturer_id } = req.body;
  if (!supplier_manufacturer_id) return res.status(400).json({ error: 'supplier_manufacturer_id is required' });

  try {
    await pool.query(
      'UPDATE supplier_manufacturers SET manufacturer_id = NULL WHERE id = $1',
      [supplier_manufacturer_id]
    );
    res.json({ success: true });
  } catch (error) {
    console.error('Hiba az alias leválasztásnál:', error);
    res.status(500).json({ error: 'Adatbázis hiba' });
  }
});

app.post('/api/unpair-all', async (req, res) => {
  const { manufacturer_id } = req.body;
  if (!manufacturer_id) return res.status(400).json({ error: 'manufacturer_id is required' });

  try {
    await pool.query(
      'UPDATE supplier_manufacturers SET manufacturer_id = NULL WHERE manufacturer_id = $1',
      [manufacturer_id]
    );
    res.json({ success: true });
  } catch (error) {
    console.error('Hiba a teljes leválasztásnál:', error);
    res.status(500).json({ error: 'Adatbázis hiba' });
  }
});

module.exports = app;



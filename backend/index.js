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
  const page = parseInt(req.query.page) || 1;
  const searchTerm = req.query.search || '';
  const limit = 20;
  const offset = (page - 1) * limit;
  // ÚJ: isActive query paraméter beolvasása
  const isActive = req.query.isActive; // Lehet 'true', 'false', vagy undefined

  let whereClauses = [];
  let queryParams = [];
  let paramIndex = 1;

  if (searchTerm) {
    whereClauses.push(`(m.name ILIKE $${paramIndex} OR sm_alias.name ILIKE $${paramIndex})`);
    queryParams.push(`%${searchTerm}%`);
    paramIndex++;
  }

  // ÚJ: is_active szűrés hozzáadása a WHERE feltételekhez
  if (isActive === 'true') {
    whereClauses.push(`m.is_active = true`);
  } else if (isActive === 'false') {
    whereClauses.push(`m.is_active = false`);
  }
  // Ha isActive undefined, nem adunk hozzá szűrést az aktivitásra

  const whereCondition = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';

  // A query-t is módosítani kell, hogy a WHERE feltételt tartalmazza
  const query = `
    SELECT
      m.id,
      m.name,
      m.is_active, -- Fontos, hogy ezt is visszaadjuk a kliensnek, ha szükséges
      (SELECT json_agg(json_build_object('id', sm.id, 'name', sm.name, 'is_active', sm.is_active)) -- Alias aktivitása is
       FROM public.supplier_manufacturers sm
       WHERE sm.manufacturer_id = m.id) as aliases,
      EXISTS (SELECT 1 FROM public.supplier_manufacturers sm_exact WHERE sm_exact.manufacturer_id = m.id AND sm_exact.name = m.name) as has_exact_match
    FROM public.manufacturers m
    LEFT JOIN public.supplier_manufacturers sm_alias ON m.id = sm_alias.manufacturer_id
    ${whereCondition}
    GROUP BY m.id, m.name, m.is_active
    ORDER BY m.name
    LIMIT $${paramIndex} OFFSET $${paramIndex + 1};
  `;
  // A queryParams-hoz hozzá kell adni a limitet és offsetet is a megfelelő helyen
  queryParams.push(limit, offset);


  try {
    // Ellenőrizzük, hogy a queryParams elemei helyes sorrendben és típusban vannak-e
    // A paramIndex alapján kell beállítani a limit és offset helyét a queryParams tömbben.
    // Az alábbi példa feltételezi, hogy a searchTerm az első, ha van.
    const finalQueryParams = [];
    let currentParamIndex = 1; // A query-ben $1, $2 stb.

    if (searchTerm) {
        finalQueryParams.push(`%${searchTerm}%`);
    }
    // Az isActive nem közvetlen paraméter a query-ben, hanem a query stringet módosítja.

    finalQueryParams.push(limit);
    finalQueryParams.push(offset);


    // A query most már így néz ki, a paramétereket $1, $2 stb. jelöli
    // A WHERE feltétel dinamikusan épül fel.
    // A queryParams-nak csak a $ jelölőkhöz tartozó értékeket kell tartalmaznia.
    // Példa: ha van searchTerm, akkor a queryParams: ['%searchTerm%', limit, offset]
    // Ha nincs searchTerm: [limit, offset]

    // Egyszerűsített paraméterkezelés a dinamikus WHERE miatt:
    const queryForExecution = `
        SELECT
          m.id,
          m.name,
          m.is_active,
          (SELECT json_agg(json_build_object('id', sm.id, 'name', sm.name, 'is_active', sm.is_active))
           FROM public.supplier_manufacturers sm
           WHERE sm.manufacturer_id = m.id) as aliases,
          EXISTS (SELECT 1 FROM public.supplier_manufacturers sm_exact WHERE sm_exact.manufacturer_id = m.id AND sm_exact.name = m.name) as has_exact_match
        FROM public.manufacturers m
        LEFT JOIN public.supplier_manufacturers sm_alias ON m.id = sm_alias.manufacturer_id AND ${searchTerm ? `sm_alias.name ILIKE $1` : '1=1'}
        <span class="math-inline">\{whereCondition\.replace\(/\\</span>\d+/g, searchTerm ? '$1' : '')}
        GROUP BY m.id, m.name, m.is_active
        ORDER BY m.name
        LIMIT ${searchTerm ? '$2' : '$1'} OFFSET ${searchTerm ? '$3' : '$2'};
    `;

    const paramsForExecution = [];
    if (searchTerm) paramsForExecution.push(`%${searchTerm}%`);
    paramsForExecution.push(limit, offset);

    const result = await pool.query(queryForExecution, paramsForExecution);
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching manufacturers with aliases:', err);
    res.status(500).send('Server error');
  }
}); 


app.get('/api/unmatched-supplier-manufacturers', async (req, res) => {
  const page = parseInt(req.query.page) || 1;
  const searchTerm = req.query.search || '';
  const isActive = req.query.isActive; // 'true', 'false', or undefined
  const limit = 20;
  const offset = (page - 1) * limit;

  let queryBase = `
    SELECT sm.id, sm.name, sm.is_active
    FROM public.supplier_manufacturers sm
    WHERE sm.manufacturer_id IS NULL
  `;
  const queryParams = [];
  let paramIndex = 1;

  if (searchTerm) {
    queryBase += ` AND sm.name ILIKE $${paramIndex}`;
    queryParams.push(`%${searchTerm}%`);
    paramIndex++;
  }

  if (isActive === 'true') {
    queryBase += ` AND sm.is_active = true`;
  } else if (isActive === 'false') {
    queryBase += ` AND sm.is_active = false`;
  }

  queryBase += ` ORDER BY sm.name LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
  queryParams.push(limit, offset);

  try {
    const result = await pool.query(queryBase, queryParams);
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching unmatched supplier manufacturers:', err);
    res.status(500).send('Server error');
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

app.post('/api/inactivate-supplier-manufacturer', async (req, res) => {
  const { supplier_manufacturer_id } = req.body;

  if (!supplier_manufacturer_id) {
    return res.status(400).json({ error: 'supplier_manufacturer_id kötelező' });
  }

    const client = await pool.connect();

  try {
    await client.query('BEGIN');

    await client.query(
      `UPDATE supplier_manufacturers
       SET is_active = FALSE
       WHERE id = $1`,
      [supplier_manufacturer_id]
    );

    await client.query('COMMIT');
    res.json({ success: true, supplier_manufacturer_id });
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


// Új gyártó nevének frissítése végpont
app.post('/api/update-manufacturer-name', async (req, res) => {
//  console.log('update-manufacturer-name body:', req.body);
  const { manufacturer_id, new_name } = req.body;
  if (!manufacturer_id || !new_name) {
    return res.status(400).json({ error: 'manufacturer_id és new_name kötelező' });
  }

  const slug = new_name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
   // console.log(new_name, '-', manufacturer_id);
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE manufacturers SET name = $1, slug = $2 WHERE id = $3`,
      [new_name, slug, manufacturer_id]
    );
    res.json({ success: true });
  } catch (error) {
    console.error('Hiba a név frissítésénél:', error);
    res.status(500).json({ error: 'Adatbázis hiba' });
  } finally {
    client.release();
  }
});

module.exports = app;

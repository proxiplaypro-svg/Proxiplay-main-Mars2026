function getTrimmedString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

// Minimal, local equivalent of index.js's toDocRef -- kept private to this
// file rather than importing from index.js, matching how other standalone
// callable modules (operator_prize_claim.js, game_qr_access.js) already
// avoid depending on index.js internals.
function toDocRef(value) {
  if (!value) return null;
  if (typeof value === 'string') {
    const path = getTrimmedString(value);
    return path && path.includes('/') ? firestore.doc(path) : null;
  }
  if (typeof value.path === 'string' && typeof value.get === 'function') {
    return value;
  }
  if (typeof value.path === 'string') {
    return firestore.doc(value.path);
  }
  return null;
}

function csvEscape(value) {
  const s = value == null ? '' : String(value);
  return /[;"\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

// dd/mm/yyyy hh:mm, UTC -- readable in a French-locale spreadsheet without
// pulling in a date-formatting dependency for one column.
function formatDateFr(value) {
  const ms =
    value && typeof value.toMillis === 'function'
      ? value.toMillis()
      : value instanceof Date
        ? value.getTime()
        : null;
  if (!Number.isFinite(ms)) return '';
  const d = new Date(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

function slugify(value) {
  const base = getTrimmedString(value) || 'jeu';
  return (
    base
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60) || 'jeu'
  );
}

const kColumns = [
  'prenom',
  'nom',
  'email',
  'telephone',
  'ville',
  'date_du_gain',
  'lot_gagne',
  'code_gagnant',
  'statut',
];
const kColumnLabels = {
  prenom: 'Prénom',
  nom: 'Nom',
  email: 'Email',
  telephone: 'Téléphone',
  ville: 'Ville',
  date_du_gain: 'Date du gain',
  lot_gagne: 'Lot gagné',
  code_gagnant: 'Code gagnant',
  statut: 'Statut',
};

// Mirrors PrizesRecord.isAvailable/isExpired (lib/backend/schema/prizes_record.dart)
// so the exported status matches what the merchant/player see in the app.
function prizeStatus(prize) {
  if (prize.claimed === true) return 'Retiré';
  const deadline = prize.usage_deadline;
  const ms =
    deadline && typeof deadline.toMillis === 'function'
      ? deadline.toMillis()
      : null;
  if (Number.isFinite(ms) && ms < Date.now()) return 'Expiré';
  return 'À retirer';
}

// "Lot gagné" must never be blank when the prize carries enough information
// to identify it -- name is the modern field, description covers older
// documents that only ever had that, and prize_type is the last resort for
// the rare historical document with neither (still better than empty).
function prizeLabel(prize) {
  const name = getTrimmedString(prize.name);
  if (name) return name;
  const description = getTrimmedString(prize.description);
  if (description) return description;
  const type = getTrimmedString(prize.prize_type);
  if (type === 'principal') return 'Lot principal';
  if (type === 'secondaire') return 'Lot secondaire';
  if (type) return type;
  return 'Lot gagné';
}

function buildCsv(rows) {
  const header = kColumns.map((c) => csvEscape(kColumnLabels[c])).join(';');
  const lines = rows.map((row) =>
    kColumns.map((c) => csvEscape(row[c])).join(';'),
  );
  // Leading UTF-8 BOM: French-locale Excel otherwise guesses a legacy
  // codepage and accented names/cities render as mojibake. ';' separator
  // matches Excel FR's default list separator (',' is the decimal mark).
  return '\uFEFF' + [header, ...lines].join('\r\n') + '\r\n';
}


async function loadGameWinners(db, gameRef, {prizeIds, fulfillmentType} = {}) {
  const docs = prizeIds ? (prizeIds.length ? await db.getAll(...prizeIds.map(id=>db.doc('prizes/'+id))) : [])
    : (await db.collection('prizes').where('game_id','==',gameRef).get()).docs;
  const entries=docs.filter(d=>d.exists).map(d=>({prizeId:d.id,prize:d.data()})).filter(e=>
    e.prize.game_id?.path===gameRef.path && /^users\/[^/]+$/.test(e.prize.winner_id?.path||'') &&
    (!fulfillmentType || e.prize.fulfillment_type===fulfillmentType));
  const refs=[...new Map(entries.map(e=>[e.prize.winner_id.path,e.prize.winner_id])).values()];
  const users=new Map((refs.length?await db.getAll(...refs):[]).map(d=>[d.ref.path,d.data()||{}]));
  return entries.map(e=>{const user=users.get(e.prize.winner_id.path)||{};return {...e,user,row:{
    prenom:getTrimmedString(user.first_name),nom:getTrimmedString(user.last_name),
    email:getTrimmedString(user.email),telephone:getTrimmedString(user.phone_number),ville:getTrimmedString(user.city),
    date_du_gain:formatDateFr(e.prize.win_date),lot_gagne:prizeLabel(e.prize),
    code_gagnant:getTrimmedString(e.prize.claim_code),statut:prizeStatus(e.prize)}};});
}
module.exports={loadGameWinners,buildCsv,slugify,prizeStatus};

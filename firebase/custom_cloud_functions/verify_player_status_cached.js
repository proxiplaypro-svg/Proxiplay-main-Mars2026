#!/usr/bin/env node

/**
 * Script de vérification du backfill player_status_cached
 * 
 * Usage:
 *   node verify_player_status_cached.js [--check-empty] [--sample-size 50]
 * 
 * Flags:
 *   --check-empty    : Cherche les users avec player_status_cached undefined/null
 *   --sample-size N  : Nombre de users à vérifier (défaut: 50)
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Charger la clé d'authentification
const serviceAccountPath = path.join(__dirname, './admin-key.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('❌ Erreur: admin-key.json non trouvé');
  console.error('   Téléchargez la clé depuis Firebase Console > Project Settings > Service Accounts');
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

const args = process.argv.slice(2);
const checkEmpty = args.includes('--check-empty');
const sampleSizeIdx = args.indexOf('--sample-size');
const sampleSize = sampleSizeIdx >= 0 && sampleSizeIdx < args.length - 1
  ? Math.max(1, Math.min(1000, parseInt(args[sampleSizeIdx + 1], 10)))
  : 50;

async function verifyPlayerStatusCached() {
  console.log('📊 Vérification du backfill player_status_cached\n');

  try {
    // 1. Statistiques globales
    console.log('1️⃣  Statistiques globales...');
    const allUsersSnap = await db.collection('users').get();
    const totalUsers = allUsersSnap.size;
    console.log(`   Total d'utilisateurs: ${totalUsers}`);

    let withStatus = 0;
    let withoutStatus = 0;
    const statuses = {};

    allUsersSnap.forEach(doc => {
      const status = doc.data().player_status_cached;
      if (status === undefined || status === null) {
        withoutStatus++;
      } else {
        withStatus++;
        statuses[status] = (statuses[status] || 0) + 1;
      }
    });

    console.log(`   Avec player_status_cached: ${withStatus} (${((withStatus / totalUsers) * 100).toFixed(1)}%)`);
    console.log(`   Sans player_status_cached: ${withoutStatus} (${((withoutStatus / totalUsers) * 100).toFixed(1)}%)`);
    console.log('\n   Distribution des statuts:');
    Object.entries(statuses).sort((a, b) => b[1] - a[1]).forEach(([status, count]) => {
      console.log(`     - ${status}: ${count}`);
    });

    // 2. Si demandé, chercher les users sans statut
    if (checkEmpty && withoutStatus > 0) {
      console.log(`\n2️⃣  Utilisateurs SANS player_status_cached (premiers 10)...`);
      const emptyQuery = db.collection('users')
        .where('player_status_cached', '==', null)
        .limit(10);

      const emptySnap = await emptyQuery.get();
      if (emptySnap.empty) {
        // Chercher ceux qui n'ont pas le champ
        const allSnap = await db.collection('users')
          .limit(10)
          .get();
        
        const withoutField = allSnap.docs.filter(doc => 
          !('player_status_cached' in doc.data())
        );

        if (withoutField.length > 0) {
          console.log(`   ${withoutField.length} utilisateurs trouvés:`);
          withoutField.forEach((doc, idx) => {
            const userData = doc.data();
            console.log(`\n   User #${idx + 1}: ${doc.id}`);
            console.log(`     - created_time: ${userData.created_time?.toDate?.() || userData.created_time || 'N/A'}`);
            console.log(`     - last_real_activity_at: ${userData.last_real_activity_at?.toDate?.() || userData.last_real_activity_at || 'N/A'}`);
            console.log(`     - games_played_count: ${userData.games_played_count || 0}`);
          });
        } else {
          console.log('   ✅ Tous les utilisateurs ont player_status_cached defini');
        }
      }
    }

    // 3. Vérification de la cohérence sur un échantillon
    console.log(`\n3️⃣  Vérification de cohérence sur ${sampleSize} utilisateurs aléatoires...`);
    const sampleSnap = await db.collection('users')
      .limit(sampleSize)
      .get();

    let coherent = 0;
    let issues = [];

    sampleSnap.forEach(doc => {
      const userData = doc.data();
      const status = userData.player_status_cached;
      const hasCreatedTime = !!userData.created_time;
      const hasGamesPlayed = typeof userData.games_played_count === 'number';

      if (!hasCreatedTime) {
        issues.push({
          uid: doc.id,
          issue: 'Pas de created_time'
        });
      } else if (status && status !== 'statut_inconnu') {
        coherent++;
      }
    });

    console.log(`   Cohérents: ${coherent}/${sampleSize}`);
    if (issues.length > 0) {
      console.log(`   Issues trovés: ${issues.length}`);
      issues.slice(0, 5).forEach(({ uid, issue }) => {
        console.log(`     - ${uid}: ${issue}`);
      });
    }

    // 4. Résumé et recommandations
    console.log('\n4️⃣  Résumé et recommandations:');
    if (withoutStatus === 0) {
      console.log('   ✅ Tous les utilisateurs ont player_status_cached!');
      console.log('   ✅ Le backfill est complet.');
    } else {
      console.log(`   ⚠️  ${withoutStatus} utilisateurs n'ont pas encore player_status_cached.`);
      console.log(`   💡 Relancez le backfill: firebase functions:call backfillPlayerStatusCached`);
    }

    console.log('\n✨ Vérification complétée!\n');

  } catch (error) {
    console.error('❌ Erreur:', error.message);
    process.exit(1);
  }
}

verifyPlayerStatusCached()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });

# Liens de jeux : preparation de mise en service

Aucun changement public n'est effectue par ce document. Les requetes observees sur proxiplay.fr sont redirigees par Vercel vers www.proxiplay.fr ; le projet Vercel proprietaire et sa configuration de domaines ne sont pas identifies dans les deux depots. Les modifications ci-dessous doivent etre faites dans ce projet et validees sur un environnement de preproduction avant publication.

## Fichiers d'association

Servir en HTTPS sans aucune redirection et avec Content-Type application/json le fichier Digital Asset Links sur chacun des trois hotes :

- https://proxiplay.fr/.well-known/assetlinks.json
- https://www.proxiplay.fr/.well-known/assetlinks.json
- https://play.proxiplay.fr/.well-known/assetlinks.json

Le fichier local hosting/.well-known/assetlinks.json contient deux empreintes existantes, dont l'attribution n'est pas verifiee ici. Comparer l'empreinte de signature d'application fournie par Play Console (Integration > Signature de l'application) avec le fichier ; conserver les empreintes encore necessaires. Ne pas confondre signature d'envoi et signature de distribution. Sur le telephone de recette precedent, la signature debug observee etait 9E:7C:D6:CD:38:D0:80:B7:71:46:A8:27:88:1C:74:B2:E3:B8:5E:F3:99:B0:97:B5:B7:7A:EF:94:F7:E9:6C:5D ; elle est propre a cette installation. L'ajout d'une signature debug a un domaine public autorise cette application a revendiquer ses liens : utiliser de preference un domaine de test distinct, ou valider explicitement l'ajout apres verification de son origine. Ne pas publier une empreinte non verifiee.

Les associations des domaines apex et www doivent etre servies directement avant tout renvoi global apex vers www ; une redirection HTTP de .well-known invalide la verification Android. Si Vercel impose une redirection de domaine avant toute regle du projet, modifier la configuration des domaines ou utiliser un frontal permettant ces exceptions. Ne pas supprimer les routes existantes du site.

## Redirection des anciennes affiches

Dans le projet qui recoit les domaines apex et www, configurer avant la redirection globale du site une regle equivalente a :

```json
{
  "source": "/j/:path+",
  "destination": "https://play.proxiplay.fr/j/:path+",
  "permanent": false
}
```

Exemple de regle Next.js ; dans Vercel natif adapter la syntaxe de destination et les conditions de domaine selon la configuration effective. Tester d'abord en 307, puis choisir 308 apres validation. Next.js transmet automatiquement la query string aux destinations ; confirmer que le frontal Vercel aussi la conserve integralement, y compris parametres repetes et qr_token, sans journaliser ces valeurs. Restreindre la regle aux deux hotes apex et www ; ne jamais l'appliquer a play.proxiplay.fr afin d'eviter une boucle. Verifier la priorite effective face au renvoi global apex vers www. Un ancien client qui suit d'abord le 308 vers www fonctionnera si la route www est bien configuree, mais la verification App Links du domaine apex exige toujours une reponse directe pour assetlinks.

## Ordre et controles

1. Identifier le projet Vercel proprietaire, l'environnement et les signatures Play ; preparer les fichiers et les exceptions pour les trois hotes, sans deployer.
2. Verifier en preproduction les deux pages web corrigees : liens publics et QR securises, parametres repetes, aucun jeton dans les journaux. Tester en particulier les intent Android et scheme iOS.
3. Apres validation explicite de mise en service, publier d'abord la page de repli et les fichiers d'association sur les hotes ; verifier chaque endpoint en HTTP 200 sans redirection, certificat et type JSON. Ne jamais ecraser les empreintes valides existantes.
4. Publier ensuite la regle des anciennes URL sur les deux hotes ; verifier les codes, Location, query string complete et absence de boucle, puis tester une affiche imprimee reelle.
5. Mettre en service l'Admin puis une application signee pour distribution, apres recette. Les QR imprimes ne changent pas et aucun document Firestore ne doit etre modifie en lot.
6. Sur Android, verifier les signatures et l'etat des trois domaines avec `adb shell pm get-app-links --user cur com.proxiplay.proxiplay`, puis scanner application installee/absente, connecte/deconnecte, jeu public/qr_only, y compris ancien QR et navigateur. Tester le retour apres connexion et verifier qu'aucune action de participation n'est declenchee lors de l'ouverture.

Le jeton de QR est actuellement conserve uniquement en memoire pendant le processus Flutter : une connexion dans le meme processus le conserve, mais apres fermeture forcee ou redemarrage le joueur doit rescanner. L'identifiant de jeu en attente, lui, peut survivre. Aucune persistance de ce justificatif n'a ete ajoutee ; la reprise automatique avec jeton apres interruption reste a concevoir et tester avec un stockage protege et une politique de suppression explicite. Apres installation depuis le store, la reprise automatique du jeu et du jeton n'est pas garantie : rescanner si necessaire.

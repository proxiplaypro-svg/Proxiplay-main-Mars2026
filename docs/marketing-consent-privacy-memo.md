# Consentement marketing joueurs — mémo juridique à valider

Avant toute newsletter, la politique de confidentialité devra préciser : la finalité (nouveaux jeux, cadeaux et actualités), la base légale (consentement), les catégories de données (adresse e-mail et preuve de consentement), les destinataires/sous-traitants, le droit de retrait à tout moment, le contact d'exercice des droits et le lien de désinscription dans chaque futur message.

Le texte de consentement proposé est : « Je souhaite recevoir par e-mail les nouveaux jeux, cadeaux à gagner et actualités de ProxiPlay. » Sa version technique est `marketing-player-v1`; tout changement substantiel exige une nouvelle version et un nouveau choix.

Les événements de consentement sont conservés trois ans après leur création (`retention_until`) afin de documenter la preuve du consentement et des retraits. Une tâche serveur de purge devra supprimer uniquement les événements dont cette date est dépassée, après validation de la durée avec le conseil juridique. Aucun envoi marketing ne doit être réalisé avant cette validation, l'implémentation du lien de désinscription et la sélection stricte des seuls consentements confirmés par le serveur.

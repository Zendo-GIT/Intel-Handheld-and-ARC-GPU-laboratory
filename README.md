# Laboratoire d'optimisation MSI Claw

Ce dépôt regroupe des diagnostics et des correctifs **spécifiques à un jeu** pour
les MSI Claw. Il est indépendant de Clawptimize Dev et de ClawTweaks.

Principes du laboratoire :

- ne jamais imposer un changement global de pilote pour corriger un seul jeu ;
- préférer les correctifs locaux, réversibles et vérifiables ;
- ne pas injecter de code dans les processus et ne pas contourner les anti-cheats ;
- conserver une sauvegarde bit-identique et une restauration vérifiée lorsqu'un
  correctif local doit modifier un fichier officiel ;
- mesurer séparément les saccades réelles et celles provoquées par un Alt+Tab.

## Cas en cours

- [Jurassic World Evolution 3 — eau sur Intel Arc](JWE3/ArcWaterFix/README.md) :
  correctif validé et publication 1.0.0 préparée pour Nexus Mods et GitHub.

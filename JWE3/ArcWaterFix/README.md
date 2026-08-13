# Jurassic World Evolution 3 — correctif expérimental de l'eau Intel Arc

## Périmètre confirmé

- Machine de référence : MSI Claw 8 AI+ Polar Tempest, Core Ultra 7 258V,
  Intel Arc 140V, 32 Go de RAM.
- Jeu de référence : Jurassic World Evolution 3 `1.4.2.0`.
- Pilote observé : Intel Graphics `32.0.101.8864`.
- Symptôme : grandes zones polygonales ou carrées qui clignotent dans l'eau et
  laissent apparaître le fond.
- Le problème persiste sans XeSS, sans OptiScaler, sans fakenvapi et quel que
  soit le réglage de qualité de l'eau.

## Résultat des premiers essais

La piste du Content Pack Cobra est **rejetée** : les variantes `lod-static` et
`flat-safe` n'ont provoqué aucun changement visible. Le pack expérimental est
donc désactivé et `Content0\Environment\Water\Water.ovl` est resté intact.

L'archive de shaders du jeu contient des chemins distincts `Win64_SM60` et
`Win64_SM65`, dont plusieurs shaders `Water_WaterPool` et
`Water_WaterVolume`. La remise à zéro des caches DirectX 12 et Intel n'a eu
aucun effet : cette piste est donc rejetée elle aussi.

Le moteur conserve séparément le niveau matériel `f3d_mesh_shader_tier`. Dans
`JWE3.exe` 1.4.2.0, le booléen interne qui autorise les mesh shaders est produit
par `setge al` à l'offset fichier `0x1CB666D`. Le correctif actuel remplace cette
instruction par `xor eax,eax; nop`, avant que le moteur ne crée ses interfaces
et pipelines. Il force ainsi le chemin classique vertex shader/SM60 sans
modifier le pilote Intel.

## Correctif actuel : fallback mesh shader

### Résultat sur la machine de référence

**Validé visuellement le 13 août 2026 : le fallback mesh shader supprime le
glitch polygonal de l'eau sur l'Intel Arc 140V avec le pilote 32.0.101.8864.**

Ce résultat confirme que le défaut se situe dans l'exécution du chemin mesh
shader SM65 sur ce pilote, et non dans les matériaux de l'eau, XeSS, le cache de
shaders ou les réglages de qualité. Le correctif reste installé sur la machine
de test.

Le gestionnaire refuse tout exécutable autre que la version testée, crée une
sauvegarde vérifiée et permet une restauration complète :

```powershell
.\tools\Manage-JWE3MeshShaderFallback.ps1 -Action Status
.\tools\Manage-JWE3MeshShaderFallback.ps1 -Action Install
.\tools\Manage-JWE3MeshShaderFallback.ps1 -Action Uninstall
```

- SHA-256 officiel :
  `04FA75D84683DE73AAFF7C0D5C28D8FDC5B4E900E5968022995CF84039F0A79F`
- SHA-256 corrigé :
  `3A172D9261075017974897A2F4EB89F16232B5E5D711B2EA77A524394BD7FAA8`
- sauvegarde : `JWE3.exe.clawlab-original-1.4.2.0.bak`

Une mise à jour du jeu ou une vérification Steam peut restaurer l'exécutable
officiel. Le gestionnaire refusera alors de réutiliser les offsets de 1.4.2.0
sur une autre version.

## Variantes de diagnostic

Une seule variante doit être active à la fois.

| Variante | Modification | But |
| --- | --- | --- |
| `lod-static` | Retire les biais de mip et fige l'animation de la texture de détail de `gst_water` | Premier essai conservateur contre les blocs animés |
| `dither-off` | Désactive le fondu tramé des matériaux de bassin | Isole un défaut de dither/roughness |
| `opacity-safe` | Augmente l'opacité liée à la profondeur | Masque un éventuel calcul de profondeur instable |
| `flat-safe` | Neutralise relief, parallaxe, distorsion et animation | Mode de secours visuellement plus plat |

## Gestion de l'ancien prototype FGM

Depuis PowerShell, dans ce dossier :

```powershell
.\tools\Manage-ArcWaterFix.ps1 -Action Status
.\tools\Manage-ArcWaterFix.ps1 -Action Install -Variant lod-static
.\tools\Manage-ArcWaterFix.ps1 -Action Disable
.\tools\Manage-ArcWaterFix.ps1 -Action Enable
.\tools\Manage-ArcWaterFix.ps1 -Action Uninstall
```

Le gestionnaire refuse toute modification lorsque `JWE3.exe` est lancé. Une
désinstallation déplace le module dans `disabled-backups` au lieu de le
supprimer.

## Test de recompilation des shaders

Le dossier DirectX `c68ef6650597d61f` a été attribué à JWE3 par sa table
`app_id`, qui contient le chemin de `JWE3.exe`. Le cache Intel associé au même
créneau d'exécution est également sauvegardé. Aucun de ces fichiers n'est un
fichier officiel du jeu.

```powershell
.\tools\Manage-JWE3ShaderCache.ps1 -Action Status
.\tools\Manage-JWE3ShaderCache.ps1 -Action Reset
.\tools\Manage-JWE3ShaderCache.ps1 -Action Restore
```

`Reset` déplace les caches dans `cache-backups` ; `Restore` remet la dernière
sauvegarde et conserve séparément le cache créé pendant le test.

## Reconstruction

La reconstruction nécessite une copie de Cobra Tools compatible JWE3 et une
extraction du `Water.ovl` officiel :

```powershell
python .\tools\build_water_variants.py `
  --cobra-tools "C:\chemin\vers\cobra-tools" `
  --water-extracted "C:\chemin\vers\Water-extracted" `
  --output .\build
```

Les fichiers du jeu restent en lecture seule pendant la reconstruction.

## Sécurité anti-cheat

Ce prototype est un remplacement de ressources Cobra pour un jeu solo. Il
n'injecte aucun hook, overlay ou DLL. Cela réduit fortement le risque par
rapport à un injecteur générique, mais ne constitue pas une garantie universelle
pour d'autres jeux. Le laboratoire n'emploiera pas ce mécanisme sur un titre
multijoueur protégé sans validation spécifique de l'éditeur et de l'anti-cheat.

Le fallback mesh shader est, lui aussi, strictement limité par nom, chemin et
hash à JWE3 1.4.2.0. Il ne lance aucun injecteur, ne modifie pas la mémoire d'un
processus et n'installe aucune DLL. La recherche locale n'a trouvé aucun binaire
Easy Anti-Cheat, BattlEye, Vanguard, EQU8, XIGNCODE ou GameGuard dans le dossier
du jeu. Un patch d'exécutable ne doit néanmoins jamais être transposé à un jeu
protégé : le laboratoire le refusera par défaut.

## Publication publique 1.0.0

Le dossier `Publish-Ready/JWE3-Intel-Arc-Water-Glitch-Fix` contient :

- `Nexus-Mods` : ZIP final, SHA-256, description prête à coller, checklist et
  capture du bug avant correction ;
- `GitHub-Repository` : dépôt public complet avec sources, README, licence MIT,
  documentation technique, règles de contribution et sécurité, modèles
  d'issues/PR et workflow GitHub Actions ;
- `ARTIFACTS_SHA256.txt` : empreinte de chaque fichier livré.

La reconstruction reproductible s'effectue avec :

```powershell
.\tools\Build-PublicationBundle.ps1 -Version 1.0.0
```

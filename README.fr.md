# Prérequis DataGalaxy sur site

Ce dépôt contient les scripts de vérification d'un cluster Kubernetes destiné à héberger DataGalaxy sur site.

| Contrôle | Script |
|----------|--------|
| Permissions du compte technique | [scripts/1.verify-permissions.bash](scripts/1.verify-permissions.bash) |
| Création dynamique de volumes persistants | [scripts/2.verify-storage.bash](scripts/2.verify-storage.bash) |
| Exposition par le contrôleur d'ingress | [scripts/3.verify-ingress.bash](scripts/3.verify-ingress.bash) |

## Prérequis

Le poste qui exécute les scripts doit disposer de :

- `bash`, `kubectl` et `curl`
- un accès au cluster avec le compte technique prévu pour l'installation (contexte `kubectl` courant)
- un accès réseau au contrôleur d'ingress, depuis l'extérieur du cluster

Ce poste ne doit pas être un nœud du cluster. Le test d'ingress vérifie l'accès depuis l'extérieur.

Côté cluster :

- l'espace de nom dédié à DataGalaxy est créé
- l'image `nginxinc/nginx-unprivileged` est accessible, ou importée dans le dépôt d'images du cluster
- l'un des deux noms de domaine prévus pour DataGalaxy pointe vers le contrôleur d'ingress

## Lancer les vérifications

Récupérer le dépôt, puis lancer les scripts dans l'ordre depuis sa racine.
Dans les exemples, `datagalaxy` est l'espace de nom et `datagalaxy.client.com` le nom de domaine.

Les scripts se paramètrent par variables d'environnement.
Commencer par indiquer l'espace de nom dédié à DataGalaxy et l'un de ses noms de domaine :

```bash
export DG_NAMESPACE=datagalaxy
export DG_DOMAIN=datagalaxy.client.com
```

L'option `-h` affiche l'aide de chaque script.

### 1. Compte technique

```bash
./scripts/1.verify-permissions.bash
```

Le script vérifie que le compte peut créer chaque type de ressource nécessaire à DataGalaxy, dans l'espace de nom et au niveau du cluster.

### 2. Stockage

```bash
./scripts/2.verify-storage.bash
DG_STORAGE_SIZE=2Gi ./scripts/2.verify-storage.bash
```

Le test est à lancer avec deux tailles différentes. À chaque exécution, le script :

1. vérifie qu'aucun volume n'est préparé à l'avance pour le PVC de test
2. crée le PVC `datagalaxy-test` et un POD qui l'utilise
3. attend que le PVC soit dans l'état `Bound`, puis contrôle la taille du volume créé
4. vérifie que le POD peut écrire sur le volume
5. supprime le PVC et vérifie que le volume disparaît

| Variable | Rôle | Défaut |
|----------|------|--------|
| `DG_NAMESPACE` | Espace de nom dédié à DataGalaxy | obligatoire |
| `DG_STORAGE_SIZE` | Taille du volume à tester | `1Gi` |
| `DG_STORAGE_CLASS` | Classe de stockage | classe par défaut du cluster |
| `DG_IMAGE` | Image du POD de test | `nginxinc/nginx-unprivileged` |
| `DG_TIMEOUT` | Délai d'attente maximal par étape, en secondes | `120` |

### 3. Contrôleur d'ingress

```bash
./scripts/3.verify-ingress.bash
```

Le script affiche les classes d'ingress, les POD du contrôleur et les services exposés hors du cluster.
L'exploitant s'appuie sur ces éléments pour décrire la liaison entre le contrôleur et le réseau extérieur.
Le script déploie ensuite une application de test, puis interroge `http://<domaine>/datagalaxy-ingress-test/index.html` et son équivalent HTTPS.
Si HTTP n'aboutit pas, le script patiente environ une minute avant de passer à HTTPS.

| Variable | Rôle | Défaut |
|----------|------|--------|
| `DG_NAMESPACE` | Espace de nom dédié à DataGalaxy | obligatoire |
| `DG_DOMAIN` | Nom de domaine prévu pour DataGalaxy | obligatoire |
| `DG_IMAGE` | Image du serveur web | `nginxinc/nginx-unprivileged` |
| `DG_INGRESS_CLASS` | Classe d'ingress | classe par défaut du cluster |
| `DG_INGRESS_IP` | Adresse IP du contrôleur, si le DNS n'est pas encore en place | résolution DNS |
| `DG_TIMEOUT` | Délai d'attente maximal du déploiement, en secondes | `120` |
| `DG_KEEP` | `true` pour conserver les ressources de test à la fin | suppression |

### Image dans un dépôt interne

Si le cluster n'accède pas à Docker Hub, importer l'image dans le dépôt interne et indiquer son nom complet avant de lancer les scripts 2 et 3 :

```bash
export DG_IMAGE=mon-depot/nginxinc/nginx-unprivileged
```

### Langue des messages

Les scripts affichent leurs messages en français ou en anglais.
La langue suit la locale du système : français si `LANG` (ou `LC_ALL`, `LC_MESSAGES`) commence par `fr`, anglais sinon.
Les textes se trouvent dans [scripts/i18n](scripts/i18n), un fichier de propriétés par langue.
La variable `DG_LANG` impose la langue :

```bash
export DG_LANG=en
```

## Lire les résultats

Chaque contrôle affiche un verdict :

- `[OK]` : le contrôle est réussi
- `[WARN]` : point de vigilance, non bloquant. L'exploitant doit le justifier (ex : volume conservé après suppression du PVC, trafic HTTP interdit).
- `[FAIL]` : le prérequis n'est pas satisfait. Une nouvelle vérification sera à planifier.
- `[INFO]` : élément de contexte, support de discussion

Un bilan termine chaque script.
Le code de sortie vaut `0` sans échec et `1` en cas d'échec.
Il vaut `2` si le script ne peut pas s'exécuter : variable obligatoire manquante, cluster injoignable ou espace de nom absent.

Les ressources de test sont supprimées à la fin de chaque script, y compris en cas d'interruption.
Avec `DG_KEEP=true`, le script 3 les conserve et indique la commande pour les supprimer.
Si un volume persistant est conservé à cause de sa politique de récupération, le script indique la commande pour le supprimer.

## Vérification manuelle

Les manifestes utilisés par les scripts se trouvent dans [k8s_manifests](k8s_manifests).
Ils peuvent aussi être appliqués à la main avec `kubectl`.
Pour le test d'ingress, remplacer d'abord `datagalaxy.int.domaine.com` par le vrai nom de domaine.

## Contribuer

Les contributions sont les bienvenues.\
Consulter le [guide de contribution](CONTRIBUTING.md).

Les scripts sont vérifiés par [ShellCheck](https://www.shellcheck.net) avant chaque commit, via [pre-commit](https://pre-commit.com).
Le hook utilise l'image Docker de ShellCheck : Docker doit être disponible sur le poste.

Pour activer le hook :

```bash
pip install pre-commit
pre-commit install
```

L'intégration continue relance ShellCheck et valide les manifestes Kubernetes avec [kubeconform](https://github.com/yannh/kubeconform).

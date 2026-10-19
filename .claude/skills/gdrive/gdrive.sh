#!/usr/bin/env bash
# gdrive.sh -- Google Drive lesen, ohne Browser-Anmeldung
#
# Der Zugriff laeuft NICHT ueber die lokale App: die hat GDRIVE_ENABLED=false,
# keine Zugangsdaten und null Nutzer mit Token. Stattdessen gibt die Produktion
# ein frisches Access-Token heraus, gegen ein Shared Secret.
#
# Das Secret steht in .env als GDRIVE_TOKEN_API_SECRET und wird von hier
# gelesen -- NIE in eine Datei schreiben, die im Repo landet.
#
# Die Root-Domain schickt einen 301, und curl verliert dabei den Header.
# Deshalb immer www. verwenden.

set -euo pipefail

REPO="${GDRIVE_REPO:-/c/Projekte_Dev/energieberatung}"
TOKEN_URL="https://www.fs-energieberater.de/api/google-drive/token"
API="https://www.googleapis.com/drive/v3/files"
# Ohne diese beiden findet die Suche nichts, was in einer geteilten Ablage liegt.
GEMEINSAM=(--data-urlencode "includeItemsFromAllDrives=true" --data-urlencode "supportsAllDrives=true")

token() {
    local secret
    secret=$(grep -m1 '^GDRIVE_TOKEN_API_SECRET=' "$REPO/.env" | cut -d= -f2- | tr -d '"'"'"' \r')
    [ -n "$secret" ] || { echo "GDRIVE_TOKEN_API_SECRET fehlt in $REPO/.env" >&2; exit 1; }
    local antwort
    antwort=$(curl -s -m 30 -H "X-App-Secret: $secret" "$TOKEN_URL")
    local t
    t=$(printf '%s' "$antwort" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
    [ -n "$t" ] || { echo "Kein Token. Antwort: $antwort" >&2; exit 1; }
    printf '%s' "$t"
}

# Die Felder einzeln herausziehen, damit es ohne jq geht (ist hier nicht da).
zeilen() {
    sed 's/},/}\n/g' \
    | awk '
        /"id":/       { gsub(/.*"id": "|".*/, ""); id = $0 }
        /"name":/     { gsub(/.*"name": "|".*/, ""); nm = $0 }
        /"mimeType":/ { gsub(/.*"mimeType": "|".*/, ""); mt = $0 }
        /}/ { if (id != "") { printf "%-46s  %-44s  %s\n", nm, id, mt; id=""; nm=""; mt="" } }
    '
}

befehl="${1:-hilfe}"

case "$befehl" in
    # Dateien und Ordner nach Namensteil suchen.
    suchen)
        T=$(token)
        curl -s -m 60 -H "Authorization: Bearer $T" -G "$API" \
            --data-urlencode "q=name contains '${2:?Suchbegriff fehlt}' and trashed = false" \
            --data-urlencode "fields=files(id,name,mimeType)" \
            --data-urlencode "pageSize=${3:-50}" "${GEMEINSAM[@]}" | zeilen
        ;;

    # Inhalt eines Ordners auflisten.
    liste)
        T=$(token)
        curl -s -m 60 -H "Authorization: Bearer $T" -G "$API" \
            --data-urlencode "q='${2:?Ordner-ID fehlt}' in parents and trashed = false" \
            --data-urlencode "fields=files(id,name,mimeType,size)" \
            --data-urlencode "pageSize=200" "${GEMEINSAM[@]}" | zeilen
        ;;

    # Name und Elternordner einer ID -- so findet man heraus, in welchem
    # Projektordner eine gefundene Datei liegt.
    wo)
        T=$(token)
        curl -s -m 60 -H "Authorization: Bearer $T" \
            "$API/${2:?ID fehlt}?fields=id,name,mimeType,parents&supportsAllDrives=true"
        echo
        ;;

    # Datei herunterladen. Google-eigene Formate (Docs, Sheets) koennen das
    # nicht -- die brauchen export, siehe unten.
    holen)
        T=$(token)
        ziel="${3:?Zielpfad fehlt}"
        curl -s -m 300 -L -H "Authorization: Bearer $T" \
            "$API/${2:?ID fehlt}?alt=media&supportsAllDrives=true" -o "$ziel"
        ls -l "$ziel"
        ;;

    # Google Docs/Sheets in ein lesbares Format exportieren.
    #   Doc  -> text/plain      Sheet -> text/csv
    export)
        T=$(token)
        curl -s -m 300 -L -H "Authorization: Bearer $T" -G \
            "$API/${2:?ID fehlt}/export" \
            --data-urlencode "mimeType=${4:-text/plain}" -o "${3:?Zielpfad fehlt}"
        ls -l "${3}"
        ;;

    # Ein Google Doc aus einer HTML-Datei anlegen. Drive wandelt beim Hochladen
    # um, wenn als Ziel-mimeType das Google-Format steht.
    #
    # Warum multipart/related von Hand: curl -F erzeugt multipart/form-data,
    # und das nimmt die Drive-API fuer den kombinierten Metadaten-plus-Inhalt-
    # Aufruf nicht an. Der Rumpf wird deshalb selbst gebaut.
    #
    # <pre> ueberlebt die Umwandlung als Courier -- ASCII-Skizzen bleiben also
    # ausgerichtet. Tabellen, Ueberschriften und Listen ebenso.
    docanlegen)
        T=$(token)
        html="${2:?HTML-Datei fehlt}"
        name="${3:?Dokumentname fehlt}"
        ordner="${4:?Ordner-ID fehlt}"
        [ -f "$html" ] || { echo "Datei nicht da: $html" >&2; exit 1; }
        G="grenze-$$-$(date +%s)"
        rumpf=$(mktemp)
        {
            printf -- "--%s\r\n" "$G"
            printf 'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            printf '{"name":"%s","parents":["%s"],"mimeType":"application/vnd.google-apps.document"}\r\n' "$name" "$ordner"
            printf -- "--%s\r\n" "$G"
            printf 'Content-Type: text/html; charset=UTF-8\r\n\r\n'
            cat "$html"
            printf '\r\n--%s--\r\n' "$G"
        } > "$rumpf"
        curl -s -m 120 -X POST \
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id,name,webViewLink" \
            -H "Authorization: Bearer $T" \
            -H "Content-Type: multipart/related; boundary=$G" \
            --data-binary @"$rumpf"
        echo
        rm -f "$rumpf"
        ;;

    # Eine beliebige Datei unveraendert hochladen -- ohne Umwandlung, anders
    # als docanlegen. Fuer .xlsx, PDF, Bilder.
    hochladen)
        T=$(token)
        datei="${2:?Datei fehlt}"
        name="${3:?Name fehlt}"
        ordner="${4:?Ordner-ID fehlt}"
        [ -f "$datei" ] || { echo "Datei nicht da: $datei" >&2; exit 1; }
        typ="${5:-application/octet-stream}"
        G="grenze-$$-$(date +%s)"
        rumpf=$(mktemp)
        {
            printf -- "--%s\r\n" "$G"
            printf 'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            printf '{"name":"%s","parents":["%s"]}\r\n' "$name" "$ordner"
            printf -- "--%s\r\n" "$G"
            printf 'Content-Type: %s\r\n\r\n' "$typ"
            cat "$datei"
            printf '\r\n--%s--\r\n' "$G"
        } > "$rumpf"
        curl -s -m 300 -X POST \
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id,name,mimeType,webViewLink" \
            -H "Authorization: Bearer $T" \
            -H "Content-Type: multipart/related; boundary=$G" \
            --data-binary @"$rumpf"
        echo
        rm -f "$rumpf"
        ;;

    *)
        cat <<'HILFE'
gdrive.sh suchen     <Namensteil> [Anzahl]
gdrive.sh liste      <Ordner-ID>
gdrive.sh wo         <ID>
gdrive.sh holen      <Datei-ID> <Zielpfad>
gdrive.sh export     <Datei-ID> <Zielpfad> [MIME, Vorgabe text/plain]
gdrive.sh docanlegen <HTML-Datei> <Dokumentname> <Ordner-ID>  # schreibt!
gdrive.sh hochladen  <Datei> <Name> <Ordner-ID> [MIME]       # schreibt!
HILFE
        ;;
esac

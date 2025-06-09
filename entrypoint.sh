#!/bin/bash

UPLOADS_PATH="/var/www/html/wp-content/uploads"
S3_ALIAS="s3"
S3_TARGET="$S3_ALIAS/$S3_BUCKET"

echo "[INIT] Configuring mc..."
mc alias set "$S3_ALIAS" "$S3_ENDPOINT" "$S3_KEY" "$S3_SECRET"

echo "[INIT] Rendering nginx.conf..."
envsubst '${S3_BUCKET} ${S3_ENDPOINT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "[INIT] Running initial full sync..."
mc mirror --overwrite "$UPLOADS_PATH" "$S3_TARGET"

echo "[WATCH] Watching $UPLOADS_PATH..."

LAST_SYNC=""
LAST_MOVED_FROM=""

inotifywait -mrq -e create,modify,delete,move "$UPLOADS_PATH" --format '%e|%w|%f' | while IFS='|' read EVENT DIR FILE; do
  FULL_PATH="$DIR$FILE"
  REL_PATH="${FULL_PATH#$UPLOADS_PATH/}"

  case "$EVENT" in
    CREATE*|MODIFY*)
      if [ -f "$FULL_PATH" ]; then
        if [ "$LAST_SYNC" != "$REL_PATH" ]; then
          echo "[SYNC] Uploading $REL_PATH"
          mc cp "$FULL_PATH" "$S3_TARGET/$REL_PATH"
          LAST_SYNC="$REL_PATH"
        fi
      fi
      ;;
    MOVED_FROM*)
      LAST_MOVED_FROM="$REL_PATH"
      ;;
    MOVED_TO*)
      if [ -n "$LAST_MOVED_FROM" ]; then
        echo "[SYNC] Deleting old path: $LAST_MOVED_FROM"
        mc rm --quiet "$S3_TARGET/$LAST_MOVED_FROM"
        LAST_MOVED_FROM=""
      fi
      if [ -f "$FULL_PATH" ]; then
        echo "[SYNC] Uploading renamed file: $REL_PATH"
        mc cp "$FULL_PATH" "$S3_TARGET/$REL_PATH"
        LAST_SYNC="$REL_PATH"
      fi
      ;;
    DELETE*)
      echo "[SYNC] Deleting $REL_PATH"
      mc rm --quiet "$S3_TARGET/$REL_PATH"
      ;;
  esac

  sleep 0.02
done &

echo "[NGINX] Starting NGINX..."
exec nginx -g 'daemon off;'

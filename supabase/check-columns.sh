#!/bin/bash
# Does the live database have every column the website writes to?
#
# Why this exists: role_title was added to the mentor signup form on
# 21 October and its migration was never run. Every mentor who tried to
# register for the next week got an error. Nothing was watching, and the
# only reason it surfaced was somebody telling Jack they couldn't sign up.
#
# Read-only. Uses the publishable key already in js/config.js, which is
# public by design. A column that exists answers [] ; one that does not
# answers 42703.
#
#   bash supabase/check-columns.sh
set -u
cd "$(dirname "$0")/.."

URL=$(grep -o 'https://[a-z0-9]*\.supabase\.co' js/config.js | head -1)
KEY=$(grep -o 'sb_publishable_[A-Za-z0-9_]*' js/config.js | head -1)
fail=0

check () {            # check <table> <column>...
  local table=$1; shift
  echo "$table"
  for col in "$@"; do
    printf '  %-24s ' "$col"
    if curl -s "$URL/rest/v1/$table?select=$col&limit=1" \
         -H "apikey: $KEY" -H "Authorization: Bearer $KEY" | grep -q 42703; then
      echo 'MISSING'; fail=1
    else
      echo 'ok'
    fi
  done
}

# Keep these lists in step with the build() functions in js/forms.js.
check pending_mentors full_name email role_title industry experience_level \
      open_to_talks is_alumnus alumnus_school_name member_contact_ok \
      public_contact public_email photo_path source

check pending_schools school_name contact_name email county status

check mentors full_name role_title industry level experience_label \
      open_to_talks is_published is_alumnus alumnus_school_name \
      member_contact_ok route_in study_field study_detail qualification bio

if [ "$fail" -ne 0 ]; then
  echo
  echo 'A MISSING column means a migration in supabase/ has not been run.'
  echo 'Find the file that adds it and run it in the Supabase SQL editor.'
  exit 1
fi
echo
echo 'All columns present.'

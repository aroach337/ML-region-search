#! /bin/bash

usage()
{
  cat <<-EOF 1>&2
    use: setup.sh [OPTIONS]*

      Options: (defaults)
        --host=HOST            Host to connect
        --xcc-port=PORT        XCC Port (9000)
        --port=PORT            App Server Port (3333)
        --prec=NUM             Precision (6)
        --db=NAME              DB name (geo-region-search)
        --forests=N            The number of forests per host (2)
        --replicas=true|false  Configure replica forests as well (true)
        --user=USER            The user for REST configuration (admin)
        --pass=PASS            The password for REST configuration (admin)
        --data-dir=DIR         The data directory ()
        --root-dir=DIR         The root directory for the application (.)
EOF
  exit 1
}
DB="geo-region-search"
NUM_FORESTS=2
REPLICAS=true
USER=admin
PASS=admin
DATA_DIR=
ROOT_DIR=$(pwd)
GROUP=Default
AUTH=$USER:$PASS
HOST=""
SKIP=""
PREC=6
XCC_PORT=9000
PORT=3333
declare -a HOSTS=()

while [ $# != 0 ]; do
  case "$1" in
    --data-dir=*)
        DATA_DIR=$(echo $1 | sed 's%--data-dir=%%')
        shift;;
    --root-dir=*)
        ROOT_DIR=$(echo $1 | sed 's%--root-dir=%%')
        shift;;
    --db=*)
        DB=$(echo $1 | sed 's%--db=%%')
        shift;;
    --prec=*)
        PREC=$(echo $1 | sed 's%--prec=%%')
        shift;;
    --forests=*)
        NUM_FORESTS=$(echo $1 | sed 's%--forests=%%')
        shift;;
    --host=*)
        HOST=$(echo $1 | sed 's%--host=%%')
        shift;;
    --xcc-port=*)
        XCC_PORT=$(echo $1 | sed 's%--xcc-port=%%')
        shift;;
    --port=*)
        PORT=$(echo $1 | sed 's%--port=%%')
        shift;;
    --pass=*)
        PASS=$(echo $1 | sed 's%--pass=%%')
        shift;;
    --replicas=*)
        REPLICAS=$(echo $1 | sed 's%--replicas=%%')
        shift;;
    --user=*)
        USER=$(echo $1 | sed 's%--user=%%')
        shift;;
    --skip)
        SKIP="true"
        shift;;
    -?)
        usage
        ;;
    *)
        echo "Bad option - $1"
        usage
       ;;
  esac
done

FOREST_PREFIX=$DB
echo $HOST
CURL="curl --anyauth --user ${USER}:${PASS} -s -S"
############################################################################
# Get the hosts that are part of the cluster, and build an array so their
# names can be found by index.

if [ -z "$HOST"  ]; then
  usage;
else

  HOSTS=($(
    $CURL -X GET -H "Accept: application/json" http://${HOST}:8002/manage/v2/hosts \
      | ./jq '.["host-default-list"]["list-items"]["list-item"][].nameref' \
      | sed 's%"%%g'
    ))
fi
NUM_HOSTS=${#HOSTS[@]}

if (( NUM_HOSTS == 1 )); then
  REPLICAS=false
fi

echo "HOSTS = ${HOSTS[@]}"


if [  -z "$SKIP" ]
then
############################################################################
# Create forests

forest_names=""
dirs=$(
  if [ "$DATA_DIR" != "" ]; then
    cat <<-EOF
    , "data-directory": "$DATA_DIR"
EOF
  fi
)
host_index=0
while ((host_index < NUM_HOSTS)); do
  host=${HOSTS[$host_index]}
  next_host=$((host_index + 1))
  declare -a replica_hosts=(${HOSTS[@]:$next_host} ${HOSTS[@]:0:$host_index})

  forest_index=1
  while (( forest_index <= NUM_FORESTS )); do
    forest_name="${FOREST_PREFIX}-$((host_index + 1))-$((forest_index))"
    forest_names="$forest_names $forest_name"

    if [ "$REPLICAS" = "true" ]; then
      replica_host_index=$(( (forest_index - 1) % (NUM_HOSTS - 1) ))
      replica_host=${replica_hosts[$replica_host_index]}
      replica_name="${forest_name}-R"
      replica_echo="with replica ${replica_name} on ${replica_host}"
      replica=$(
        cat <<-EOF
        , "forest-replicas":
            { "forest-replica":
                [ { "replica-name": "${replica_name}",
                    "host": "$replica_host"
                    $dirs
                  }
                ]
            }
EOF
      )
    fi
    echo "Creating  $forest_name on $host $replica_echo"

    $CURL -X POST -H "Content-type: application/json" -d @- http://${HOST}:8002/manage/v2/forests <<-EOF
    { "forest-name": "$forest_name",
      "host": "$host"
      $dirs
      $replica
    }
EOF
    forest_index=$((forest_index + 1))
  done
  host_index=$((host_index + 1))
done

echo "Creating database $DB"
$CURL -X POST -d @- -H "Content-type: application/json" http://${HOST}:8002/manage/v2/databases <<-EOF
    { "database-name" : "$DB",
      "security-database": "Security",
      "schema-database": "Schemas",
      "forest":
        [ $( declare -a tmp=($forest_names)
             i=0
             while (( i < ${#tmp[@]} )); do
               if (( i > 0 )); then
                 echo -n ", "
               fi
               echo -n \"${tmp[i]}\"
               i=$((i + 1))
             done
           )
        ],
      "stemmed-searches": "off",
      "word-searches": false,
      "word-positions": false,
      "fast-phrase-searches": false,
      "fast-reverse-searches": false,
      "triple-index": false,
      "triple-positions": false,
      "fast-case-sensitive-searches": false,
      "fast-diacritic-sensitive-searches": false,
      "fast-element-word-searches": false,
      "uri-lexicon": true,
      "path-namespace": [
        { "prefix": "foo",
          "namespace-uri": "http://marklogic.com/foo"
        }
      ],
      "geospatial-region-path-index": [
         { "path-expression": "//foo:region",
           "coordinate-system": "wgs84",
           "geohash-precision": $PREC,
           "invalid-values": "reject"
         }
      ]
    }
EOF


echo "Creating load app server"
$CURL -X POST -d @- -H "Content-type: application/json" \
  "http://${HOST}:8002/manage/v2/servers" <<-EOF
    { "server-name": "$XCC_PORT-xcc",
      "server-type": "xdbc",
      "group-name": "$GROUP",
      "root": "/ext/$DB/",
      "port": $XCC_PORT,
      "content-database": "$DB",
      "modules-database": "Modules",
      "threads": 64
    }
EOF

echo "Creating demo app server"
$CURL -X POST -d @- -H "Content-type: application/json" \
      "http://${HOST}:8002/manage/v2/servers" <<-EOF
    { "server-name": "$DB-server",
      "server-type": "http",
      "group-name": "$GROUP",
      "root": "$ROOT_DIR",
      "port": $PORT,
      "content-database": "$DB",
      "modules-database": "file-system",
      "threads": 64,
      "default-user": "$USER",
      "authentication": "application-level"
    }
EOF

fi #SKIP

#for i in test.xqy
#do
#  echo "Uploading $i to http://$HOST:8000/v1/ext/$DB/$i"
#  curl -s --anyauth --user $AUTH -X PUT  --data-binary @../xquery/$i  "http://$HOST:8000/v1/ext/$DB/$i?format=text"
#done

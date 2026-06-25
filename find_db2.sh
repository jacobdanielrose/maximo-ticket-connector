# This searches ALL namespaces for DB2
for ns in $(oc get projects -o name | cut -d'/' -f2); do
  DB2_PODS=$(oc get pods -n $ns 2>/dev/null | grep -i db2 | head -n 1)
  if [ ! -z "$DB2_PODS" ]; then
    echo "✅ Found DB2 in namespace: $ns"
  fi
done


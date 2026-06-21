dns_name="faresahmed.link"
full_sub_domain="srv2.$dns_name"

get_hosted_zone_id() {
    hosted_zone_id=$(aws route53 list-hosted-zones-by-name --query "HostedZones[?Name == '$dns_name.']"  | grep -oP '(?<="Id": ")[^"]*' | uniq)

    if [[ "$hosted_zone_id" == "" ]]; then
        echo "Hosted Zone Not Exists ..."
        exit 1
    else
        hosted_zone_id=$(echo "$hosted_zone_id" | sed 's/\/hostedzone\///')
        echo "Hosted Zone Id: $hosted_zone_id"
    fi
}

create_dns_record() {
    if [[ "$env" != "prod" ]]; then
        full_sub_domain="$env-$full_sub_domain"
    fi

    create_change=$(cat << EOF
{
  "Changes": 
  [
    {
      "Action": "CREATE",
      "ResourceRecordSet": 
      {
        "Name": "${full_sub_domain}",
        "Type": "A",
        "AliasTarget":{
          "HostedZoneId": "${elb_hostedzone_id}",
          "DNSName": "${elb_dns_name}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
)

    create_change=$(echo $create_change | tr -d '\n' | tr -d ' ')
    
    check_record=$(aws route53 list-resource-record-sets --hosted-zone-id $hosted_zone_id \
            --query "ResourceRecordSets[?Name == '$full_sub_domain.'] | [0]")
    
    echo "check_record:"
    echo $check_record
    if [[ "$check_record" == "null" ]]; then
        echo "DNS Record will be created ..."
        record_change=$(aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch $create_change)
        echo $record_change
    else
        check_record_hostzone_name=$(echo "$check_record" | grep -oP '(?<="DNSName": ")[^"]*')
        echo "check record hostzone name"
        echo $check_record_hostzone_name

        if [[ "${check_record_hostzone_name}" != "${elb_dns_name}." ]]; then
            echo "DNS Record pointing to the wrong elb, Recreating..."
            delete_dns_record

            echo "DNS Record will be created ..."
            record_change=$(aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch $create_change)
            echo $record_change
        else
            echo "DNS Record already exist."
        fi
    fi
}

delete_dns_record() {
        delete_change=$(cat << EOF
{
  "Changes": 
  [
    {
      "Action": "DELETE",
      "ResourceRecordSet": ${check_record}
    }
  ]
}
EOF
)

    delete_change=$(echo $delete_change | tr -d '\n' | tr -d ' ')

    echo "Deleting Record..."
    record_change=$(aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch $delete_change)
    echo $record_change
}

get_hosted_zone_id
create_dns_record
echo

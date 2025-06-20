public with sharing class NearbyRecordsHandler {
    
    // Configuration for different object types - easily extensible
    private static Map<String, ObjectConfig> objectConfigs = new Map<String, ObjectConfig>{
        'lead' => new ObjectConfig(
            'Lead',
            new List<String>{'Name', 'Company', 'Email', 'Phone'},
            new Map<String, String>{'Name' => 'Lead Name', 'Company' => 'Company', 'Email' => 'Email', 'Phone' => 'Phone'},
            'Property_Latitude__c',
            'Property_Longitude__c',
            '00Q'
        ),
        'property' => new ObjectConfig(
            'Property__c',
            new List<String>{'Name', 'Price__c', 'Address__c', 'Type__c'},
            new Map<String, String>{'Name' => 'Property Name', 'Price__c' => 'Price', 'Address__c' => 'Address', 'Type__c' => 'Type'},
            'Latitude__c',
            'Longitude__c',
            'a0A'
        )
    };
    
    public class ObjectConfig {
        public String objectApiName;
        public List<String> displayFields;
        public Map<String, String> fieldLabels;
        public String latitudeField;
        public String longitudeField;
        public String recordPrefix;
        
        public ObjectConfig(String objectApiName, List<String> displayFields, Map<String, String> fieldLabels, 
                           String latitudeField, String longitudeField, String recordPrefix) {
            this.objectApiName = objectApiName;
            this.displayFields = displayFields;
            this.fieldLabels = fieldLabels;
            this.latitudeField = latitudeField;
            this.longitudeField = longitudeField;
            this.recordPrefix = recordPrefix;
        }
    }

    public class InputWrapper {
        @InvocableVariable public String userPrompt;
        @InvocableVariable public String recordId;
    }

    public class OutputWrapper {
        @InvocableVariable public String result;
    }

    @InvocableMethod(label='Find Nearby Records')
    public static List<OutputWrapper> getNearby(List<InputWrapper> inputs) {
        InputWrapper input = inputs[0];
        String prompt = input.userPrompt != null ? input.userPrompt.toLowerCase() : '';
        String recordId = input.recordId;

        if (String.isBlank(recordId)) {
            return wrap('❌ No recordId found.');
        }

        // Determine object type from prompt or record ID
        String objectType = determineObjectType(prompt, recordId);
        if (objectType == null) {
            return wrap('❌ Could not identify target object. Supported objects: ' + String.join(objectConfigs.keySet(), ', '));
        }

        // Extract radius from prompt
        Decimal radius = extractRadius(prompt);

        // Get current record coordinates
        RecordLocation currentLocation = getCurrentRecordLocation(recordId, objectType);
        if (currentLocation == null) {
            return wrap('❌ Could not retrieve location data for current record.');
        }

        // Find nearby records
        List<Map<String, Object>> nearbyRecords = findNearbyRecords(objectType, currentLocation, radius, recordId);
        
        // Build and return result
        String result = buildResultString(nearbyRecords, currentLocation, objectType, radius);
        return wrap(result);
    }

    private static String determineObjectType(String prompt, String recordId) {
        // First check prompt for explicit object mention
        for (String objectType : objectConfigs.keySet()) {
            if (prompt.contains(objectType)) {
                return objectType;
            }
        }
        
        // Fallback to record ID prefix
        String prefix = recordId.left(3);
        for (String objectType : objectConfigs.keySet()) {
            if (objectConfigs.get(objectType).recordPrefix == prefix) {
                return objectType;
            }
        }
        
        return null;
    }

    private static Decimal extractRadius(String prompt) {
        Pattern p = Pattern.compile('(\\d+\\.?\\d*)\\s*mile');
        Matcher m = p.matcher(prompt);
        return m.find() ? Decimal.valueOf(m.group(1)) : 10; // Default 10 miles
    }

    private static RecordLocation getCurrentRecordLocation(String recordId, String objectType) {
        ObjectConfig config = objectConfigs.get(objectType);
        
        try {
            String query = 'SELECT Name, ' + config.latitudeField + ', ' + config.longitudeField + 
                          ' FROM ' + config.objectApiName + ' WHERE Id = :recordId LIMIT 1';
            
            SObject record = Database.query(query)[0];
            
            return new RecordLocation(
                (String) record.get('Name'),
                (Decimal) record.get(config.latitudeField),
                (Decimal) record.get(config.longitudeField)
            );
        } catch (Exception e) {
            System.debug('Error retrieving current record location: ' + e.getMessage());
            return null;
        }
    }

    private static List<Map<String, Object>> findNearbyRecords(String objectType, RecordLocation currentLocation, Decimal radius, String excludeRecordId) {
        ObjectConfig config = objectConfigs.get(objectType);
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        
        // Build dynamic query with display fields
        String fields = String.join(config.displayFields, ', ');
        String query = 'SELECT Id, ' + fields + ', ' + config.latitudeField + ', ' + config.longitudeField + 
                      ' FROM ' + config.objectApiName + 
                      ' WHERE Id != :excludeRecordId AND ' + config.latitudeField + ' != null AND ' + config.longitudeField + ' != null' +
                      ' LIMIT 200'; // Reasonable limit for distance calculation
        
        Map<String, Object> bindVars = new Map<String, Object>{'excludeRecordId' => excludeRecordId};
        
        for (SObject record : Database.queryWithBinds(query, bindVars, AccessLevel.USER_MODE)) {
            Decimal lat = (Decimal) record.get(config.latitudeField);
            Decimal lng = (Decimal) record.get(config.longitudeField);
            
            Double distance = haversine(currentLocation.latitude, currentLocation.longitude, lat, lng);
            
            if (distance <= radius) {
                Map<String, Object> recordData = new Map<String, Object>{
                    'id' => record.Id,
                    'name' => (String) record.get('Name'),
                    'distance' => distance,
                    'latitude' => lat,
                    'longitude' => lng,
                    'fields' => new Map<String, Object>()
                };
                
                // Add display fields
                for (String field : config.displayFields) {
                    ((Map<String, Object>) recordData.get('fields')).put(field, record.get(field));
                }
                
                records.add(recordData);
            }
        }

        // Sort by distance
        records.sort(new DistanceComparator());
        
        // Return max 30 records
        return records.size() > 30 ? records.subList(0, 30) : records;
    }

    private static String buildResultString(List<Map<String, Object>> records, RecordLocation currentLocation, String objectType, Decimal radius) {
        ObjectConfig config = objectConfigs.get(objectType);
        List<String> resultLines = new List<String>();
        
        if (records.isEmpty()) {
            return '❌ No ' + objectType + 's found within ' + radius + ' miles.';
        }
        
        resultLines.add('📍 Found ' + records.size() + ' ' + objectType + '(s) within ' + radius + ' miles:\n');
        
        Integer displayLimit = Math.min(records.size(), 30);
        
        for (Integer i = 0; i < displayLimit; i++) {
            Map<String, Object> record = records[i];
            String recordName = (String) record.get('name');
            String recordId = (String) record.get('id');
            Double distance = (Double) record.get('distance');
            Map<String, Object> fields = (Map<String, Object>) record.get('fields');
            
            // Build clickable record entry
            String line = '• **[' + recordName + '](/lightning/r/' + recordId + '/view)**';
            
            // Add display fields
            for (String field : config.displayFields) {
                if (field != 'Name' && fields.get(field) != null) {
                    String fieldLabel = config.fieldLabels.get(field);
                    Object fieldValue = fields.get(field);
                    line += '\n  ' + fieldLabel + ': ' + String.valueOf(fieldValue);
                }
            }
            
            line += '\n  Distance: ' + Decimal.valueOf(distance).setScale(2) + ' miles\n';
            resultLines.add(line);
        }

        // Generate map URL
        String mapUrl = generateMapUrl(records, currentLocation, displayLimit);
        resultLines.add('\n📍 **[Click here to see this on Map](' + mapUrl + ')**');
        
        return String.join(resultLines, '\n');
    }

    private static String generateMapUrl(List<Map<String, Object>> records, RecordLocation currentLocation, Integer limit) {
        List<Map<String, Object>> markerList = new List<Map<String, Object>>();
        
        // Add current location marker
        markerList.add(new Map<String, Object>{ 
            'name' => currentLocation.name + ' (Current)', 
            'lat' => currentLocation.latitude, 
            'lng' => currentLocation.longitude, 
            'color' => 'red' 
        });

        // Add nearby records markers
        for (Integer i = 0; i < limit; i++) {
            Map<String, Object> record = records[i];
            markerList.add(new Map<String, Object>{ 
                'name' => (String) record.get('name'), 
                'lat' => record.get('latitude'), 
                'lng' => record.get('longitude'), 
                'color' => 'blue' 
            });
        }

        String encoded = EncodingUtil.urlEncode(JSON.serialize(markerList), 'UTF-8');
        return 'https://tanishdragonemperor.github.io/property-map/map.html?lat=' + currentLocation.latitude + 
               '&lng=' + currentLocation.longitude + '&markers=' + encoded;
    }

    private static Double haversine(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Double R = 3958.8; // Radius of Earth in miles
        Double dLat = ((Double)(lat2 - lat1)) * (Math.PI / 180);
        Double dLon = ((Double)(lon2 - lon1)) * (Math.PI / 180);
        Double lat1Rad = ((Double)lat1) * (Math.PI / 180);
        Double lat2Rad = ((Double)lat2) * (Math.PI / 180);
 
        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                   Math.cos(lat1Rad) * Math.cos(lat2Rad) *
                   Math.sin(dLon / 2) * Math.sin(dLon / 2);
        
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    private static List<OutputWrapper> wrap(String result) {
        OutputWrapper output = new OutputWrapper();
        output.result = result;
        return new List<OutputWrapper>{ output };
    }

    // Helper classes
    public class RecordLocation {
        public String name;
        public Decimal latitude;
        public Decimal longitude;
        
        public RecordLocation(String name, Decimal latitude, Decimal longitude) {
            this.name = name;
            this.latitude = latitude;
            this.longitude = longitude;
        }
    }

    private class DistanceComparator implements Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            Double distA = (Double) a.get('distance');
            Double distB = (Double) b.get('distance');
            return distA < distB ? -1 : (distA > distB ? 1 : 0);
        }
    }
}
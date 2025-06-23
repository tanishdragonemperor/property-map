public with sharing class NearbyRecordsHandler {
    // Configuration for different object types - easily extensible
    private static Map<String, ObjectConfig> objectConfigs = new Map<String, ObjectConfig>{
        'lead' => new ObjectConfig(
            'Lead',
            new List<String>{'Name', 'Company', 'Status', 'Property_Name__c', 'Property_Address__c', 'Property_Age_In_Years__c'},
            new Map<String, String>{
                'Name' => 'Lead Name',
                'Company' => 'Company',
                'Status' => 'Status',
                'Property_Name__c' => 'Property Name',
                'Property_Address__c' => 'Property Address',
                'Property_Age_In_Years__c' => 'Property Age (Years)'
            },
            'Property_Latitude__c',
            'Property_Longitude__c',
            '00Q'
        ),
        'property' => new ObjectConfig(
            'Property__c',
            new List<String>{'Name', 'Source_Contact_First_Name__c', 'Source_Contact_Last_Name__c', 'apiCount__c'},
            new Map<String, String>{
                'Name' => 'Property Name',
                'Source_Contact_First_Name__c' => 'Source Contact First Name',
                'Source_Contact_Last_Name__c' => 'Source Contact Last Name',
                'apiCount__c' => 'API Count'
            },
            'Latitude__c',
            'Longitude__c',
            'a0A'
        )
    };
    
    // List of colors for random assignment
    private static List<String> markerColors = new List<String>{
        'blue', 'green', 'purple', 'orange', 'yellow', 'pink', 'cyan', 'magenta', 'lime', 'brown'
    };

    /** 
     * Configuration class for different object types
     */
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

    /** 
     * Input wrapper for Flow integration
     */
    public class InputWrapper {
        @InvocableVariable(label='User Prompt' description='Natural language prompt describing what to search for')
        public String userPrompt;
        
        @InvocableVariable(label='Record ID' description='ID of the anchor record to search around')
        public String recordId;
    }

    /** 
     * Output wrapper for Flow integration
     */
    public class OutputWrapper {
        @InvocableVariable(label='Search Results' description='HTML formatted results of nearby records search')
        public String result;
    }

    /**
     * Main entrypoint for the Flow/Agent. 
     * Always uses the anchor record's coordinates and searches for nearby records of the specified type.
     */
    @InvocableMethod(label='Find Nearby Records' description='Finds records near a given location based on natural language prompt')
    public static List<OutputWrapper> getNearby(List<InputWrapper> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return wrap('❌ No input provided.');
        }
        
        InputWrapper input = inputs[0];
        String prompt = input.userPrompt != null ? input.userPrompt.toLowerCase().trim() : '';
        String recordId = input.recordId != null ? input.recordId.trim() : '';

        if (String.isBlank(recordId)) {
            return wrap('❌ No recordId provided.');
        }

        if (String.isBlank(prompt)) {
            return wrap('❌ No search prompt provided.');
        }

        try {
            // 1. Parse target search object type from the prompt
            String searchObjectType = determineSearchObjectType(prompt);
            if (searchObjectType == null) {
                return wrap('❌ Could not identify target object. Supported objects: ' + String.join(objectConfigs.keySet(), ', ') + '. Try saying "find leads near me" or "show properties nearby".');
            }

            // 2. Determine anchor object type (by recordId prefix)
            String anchorObjectType = determineObjectTypeFromRecordId(recordId);
            if (anchorObjectType == null) {
                return wrap('❌ Could not identify anchor record object type from ID: ' + recordId);
            }

            // 3. Query anchor record's location
            RecordLocation anchorLocation = getCurrentRecordLocation(recordId, anchorObjectType);
            if (anchorLocation == null) {
                return wrap('❌ Could not retrieve location data for anchor record. Ensure the record has valid latitude/longitude coordinates.');
            }

            // 4. Parse radius from prompt (default to 10)
            Decimal radius = extractRadius(prompt);

            // 5. Find nearby records of target type, using anchor's lat/long
            List<Map<String, Object>> nearbyRecords = findNearbyRecords(searchObjectType, anchorLocation, radius, recordId);

            // 6. Build result string
            String result = buildResultString(nearbyRecords, anchorLocation, searchObjectType, radius);
            return wrap(result);
            
        } catch (Exception e) {
            System.debug('Error in getNearby: ' + e.getMessage());
            return wrap('❌ An error occurred while searching for nearby records: ' + e.getMessage());
        }
    }

    /**
     * Determines the search object type from natural language prompt
     */
    private static String determineSearchObjectType(String prompt) {
        // Check for plural forms and common variations
        if (prompt.contains('lead') || prompt.contains('leads')) {
            return 'lead';
        }
        if (prompt.contains('property') || prompt.contains('properties')) {
            return 'property';
        }
        
        // Fallback to exact matches
        for (String objectType : objectConfigs.keySet()) {
            if (prompt.contains(objectType)) {
                return objectType;
            }
        }
        return null;
    }

    /**
     * Determines object type from Salesforce record ID prefix
     */
    private static String determineObjectTypeFromRecordId(String recordId) {
        if (String.isBlank(recordId) || recordId.length() < 3) {
            return null;
        }
        
        String prefix = recordId.substring(0, 3);
        for (String objectType : objectConfigs.keySet()) {
            if (objectConfigs.get(objectType).recordPrefix.equals(prefix)) {
                return objectType;
            }
        }
        return null;
    }

    /**
     * Extracts radius from prompt, defaults to 10 miles
     */
    private static Decimal extractRadius(String prompt) {
        Pattern p = Pattern.compile('(\\d+(?:\\.\\d+)?)\\s*mile');
        Matcher m = p.matcher(prompt);
        if (m.find()) {
            try {
                return Decimal.valueOf(m.group(1));
            } catch (Exception e) {
                System.debug('Error parsing radius: ' + e.getMessage());
            }
        }
        return 10; // Default 10 miles
    }

    /**
     * Gets the location coordinates of the current record
     */
    private static RecordLocation getCurrentRecordLocation(String recordId, String objectType) {
        ObjectConfig config = objectConfigs.get(objectType);
        if (config == null) {
            return null;
        }
        
        try {
            String query = 'SELECT Name, ' + config.latitudeField + ', ' + config.longitudeField + 
                           ' FROM ' + config.objectApiName + ' WHERE Id = :recordId LIMIT 1';
            
            List<SObject> results = Database.query(query);
            if (results.isEmpty()) {
                return null;
            }
            
            SObject record = results[0];
            Decimal latitude = (Decimal) record.get(config.latitudeField);
            Decimal longitude = (Decimal) record.get(config.longitudeField);
            
            if (latitude == null || longitude == null) {
                return null;
            }
            
            return new RecordLocation(
                (String) record.get('Name'),
                latitude,
                longitude
            );
        } catch (Exception e) {
            System.debug('Error retrieving current record location: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Finds nearby records within the specified radius
     */
    private static List<Map<String, Object>> findNearbyRecords(String objectType, RecordLocation anchorLocation, 
                                                               Decimal radius, String excludeRecordId) {
        ObjectConfig config = objectConfigs.get(objectType);
        List<Map<String, Object>> records = new List<Map<String, Object>>();

        try {
            // Build dynamic SOQL query with fields for this object
            String fields = String.join(config.displayFields, ', ');
            String query = 'SELECT Id, ' + fields + ', ' + config.latitudeField + ', ' + config.longitudeField +
                           ' FROM ' + config.objectApiName +
                           ' WHERE Id != :excludeRecordId AND ' + config.latitudeField + ' != null AND ' + 
                           config.longitudeField + ' != null LIMIT 200';
            
            Map<String, Object> bindVars = new Map<String, Object>{'excludeRecordId' => excludeRecordId};

            for (SObject record : Database.queryWithBinds(query, bindVars, AccessLevel.USER_MODE)) {
                Decimal lat = (Decimal) record.get(config.latitudeField);
                Decimal lng = (Decimal) record.get(config.longitudeField);

                if (lat != null && lng != null) {
                    Double distance = haversine(anchorLocation.latitude, anchorLocation.longitude, lat, lng);
                    if (distance <= radius) {
                        Map<String, Object> recordData = new Map<String, Object>{
                            'id' => record.Id,
                            'name' => (String) record.get(getNameField(config)),
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
            }
            
            // Sort by distance
            records.sort(new DistanceComparator());

            // Return up to 30 records
            return records.size() > 30 ? records.subList(0, 30) : records;
            
        } catch (Exception e) {
            System.debug('Error finding nearby records: ' + e.getMessage());
            return new List<Map<String, Object>>();
        }
    }

    /**
     * Gets the name field for the object
     */
    private static String getNameField(ObjectConfig config) {
        return config.displayFields.contains('Name') ? 'Name' : config.displayFields[0];
    }

    /**
     * Builds the HTML result string
     */
    private static String buildResultString(List<Map<String, Object>> records, RecordLocation anchorLocation, 
                                          String objectType, Decimal radius) {
        ObjectConfig config = objectConfigs.get(objectType);
        List<String> resultLines = new List<String>();

        if (records.isEmpty()) {
            String coordInfo = 'lat:' + anchorLocation.latitude + ',lng:' + anchorLocation.longitude + ',name:' + anchorLocation.name;
            return '❌ No ' + objectType + 's found within ' + radius + ' miles of ' + anchorLocation.name + '. [' + coordInfo + ']';
        }

        // Start with HTML structure and embed coordinates for context
        String coordInfo = 'lat:' + anchorLocation.latitude + ',lng:' + anchorLocation.longitude + ',name:' + anchorLocation.name;
        resultLines.add('<div>');
        resultLines.add('<p><strong>📍 Found ' + records.size() + ' ' + objectType + '(s) within ' + radius + ' miles of ' + anchorLocation.name + '</strong></p>');
        resultLines.add('<!-- Coordinates: ' + coordInfo + ' -->');

        Integer displayLimit = Math.min(records.size(), 30);
        for (Integer i = 0; i < displayLimit; i++) {
            Map<String, Object> record = records[i];
            String recordName = (String) record.get('name');
            String recordId = (String) record.get('id');
            Double distance = (Double) record.get('distance');
            Map<String, Object> fields = (Map<String, Object>) record.get('fields');

            resultLines.add('<div style="margin-bottom: 15px; padding: 10px; border-left: 2px solid #0070d2;">');
            
            // Main record link
            String escapedName = String.isNotBlank(recordName) ? String.escapeSingleQuotes(recordName) : 'Unnamed Record';
            resultLines.add('<p>• <a href="/lightning/r/' + recordId + '/view" target="_blank">' + escapedName + '</a></p>');

            // Add display fields
            for (String field : config.displayFields) {
                if (field != 'Name' && fields.get(field) != null) {
                    String fieldLabel = config.fieldLabels.get(field);
                    Object fieldValue = fields.get(field);
                    if (fieldLabel != null && fieldValue != null) {
                        resultLines.add('<p style="margin-left: 20px; color: #666; font-size: 0.9em;">' + 
                                      fieldLabel + ': ' + String.valueOf(fieldValue) + '</p>');
                    }
                }
            }
            resultLines.add('<p style="margin-left: 20px; color: #666; font-size: 0.9em;">Distance: ' + 
                          Decimal.valueOf(distance).setScale(2) + ' miles</p>');
            resultLines.add('</div>');
        }

        // Generate map URL
        String mapUrl = generateMapUrl(records, anchorLocation, displayLimit);
        resultLines.add('<p style="text-align: center; margin-top: 20px;">');
        resultLines.add('<a href="' + mapUrl + '" target="_blank" style="background-color: #0070d2; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px;">📍 View All on Map</a>');
        resultLines.add('</p>');
        
        // Add helpful note
        resultLines.add('<p style="text-align: center; margin-top: 10px; font-size: 0.85em; color: #666;">');
        resultLines.add('💡 <em>You can search for other object types from this location by saying "show [leads/properties] near me"</em>');
        resultLines.add('</p>');
        
        resultLines.add('</div>');

        return String.join(resultLines, '');
    }

    /**
     * Generates the map URL with markers
     */
    private static String generateMapUrl(List<Map<String, Object>> records, RecordLocation anchorLocation, Integer lim) {
        List<Map<String, Object>> markerList = new List<Map<String, Object>>();

        // Add anchor location marker (always red)
        markerList.add(new Map<String, Object>{
            'name' => anchorLocation.name + ' (Current)',
            'lat' => anchorLocation.latitude,
            'lng' => anchorLocation.longitude,
            'color' => 'red'
        });

        // Add nearby records markers with random colors
        for (Integer i = 0; i < lim && i < records.size(); i++) {
            Map<String, Object> record = records[i];
            String randomColor = getRandomColor(i);
            
            markerList.add(new Map<String, Object>{
                'name' => (String) record.get('name'),
                'lat' => record.get('latitude'),
                'lng' => record.get('longitude'),
                'color' => randomColor
            });
        }

        String encoded = EncodingUtil.urlEncode(JSON.serialize(markerList), 'UTF-8');
        return 'https://tanishdragonemperor.github.io/property-map/map.html?lat=' + anchorLocation.latitude + 
               '&lng=' + anchorLocation.longitude + '&markers=' + encoded;
    }

    /**
     * Gets a random color for map markers
     */
    private static String getRandomColor(Integer index) {
        Integer colorIndex = Math.mod(Math.abs(index), markerColors.size());
        return markerColors[colorIndex];
    }

    /**
     * Calculates distance between two coordinates using Haversine formula
     */
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

    /**
     * Wraps result in OutputWrapper for Flow
     */
    private static List<OutputWrapper> wrap(String result) {
        OutputWrapper output = new OutputWrapper();
        output.result = result;
        return new List<OutputWrapper>{ output };
    }

    /**
     * Helper class to store record location data
     */
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

    /**
     * Comparator to sort records by distance
     */
    private class DistanceComparator implements Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            Double distA = (Double) a.get('distance');
            Double distB = (Double) b.get('distance');
            if (distA == null && distB == null) return 0;
            if (distA == null) return 1;
            if (distB == null) return -1;
            return distA < distB ? -1 : (distA > distB ? 1 : 0);
        }
    }
}
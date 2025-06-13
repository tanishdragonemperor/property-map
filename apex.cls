public with sharing class NearbyPropertyMapService {
    public class InputWrapper {
        @InvocableVariable public String userPrompt;
    }

    public class ResponseWrapper {
        @InvocableVariable public String result;
    }

    @InvocableMethod(label='Find Nearby Properties and Show Map')
    public static List<ResponseWrapper> getMapFromPrompt(List<InputWrapper> inputs) {
        String prompt = inputs[0].userPrompt;
        Pattern p = Pattern.compile('([-+]?\\d*\\.?\\d+),\\s*([-+]?\\d*\\.?\\d+).*?(\\d+).*?mile');
        Matcher m = p.matcher(prompt);

        if (!m.find()) {
            return wrap('❌ Could not understand your location or radius.');
        }

        Decimal lat = Decimal.valueOf(m.group(1));
        Decimal lng = Decimal.valueOf(m.group(2));
        Decimal radius = Decimal.valueOf(m.group(3));

        List<Listing__c> listings = [
            SELECT Name, Latitude__c, Longitude__c 
            FROM Listing__c 
            WHERE Latitude__c != null AND Longitude__c != null
        ];

        List<Listing__c> nearby = new List<Listing__c>();
        for (Listing__c l : listings) {
            if (haversine(lat, lng, l.Latitude__c, l.Longitude__c) <= radius) {
                nearby.add(l);
            }
        }

        List<String> colors = new List<String>{'red','blue','green','orange','purple','yellow','black','brown','cyan','pink'};
        Integer i = 0;

        List<Map<String, Object>> markerList = new List<Map<String, Object>>();
        for (Listing__c l : nearby) {
            Integer index = Math.mod(i, colors.size());
            String color = colors[index];

            Map<String, Object> marker = new Map<String, Object>{
                'name' => l.Name,
                'lat' => l.Latitude__c,
                'lng' => l.Longitude__c,
                'color' => color
            };
            markerList.add(marker);
            i++;
        }

        String markerJson = EncodingUtil.urlEncode(JSON.serialize(markerList), 'UTF-8');
        String mapUrl = 'https://tanishdragonemperor.github.io/property-map/map.html'
                        + '?lat=' + lat + '&lng=' + lng + '&markers=' + markerJson;

        return wrap('✅ [Click here to view properties on map](' + mapUrl + ')');
    }

    private static Double haversine(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Double R = 3958.8;
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

    private static List<ResponseWrapper> wrap(String s) {
        ResponseWrapper r = new ResponseWrapper();
        r.result = s;
        return new List<ResponseWrapper>{ r };
    }
}








public with sharing class NearbyMapFromPromptHandler {

    public class InputWrapper {
        @InvocableVariable public String userPrompt;
        @InvocableVariable public String recordId;
    }

    public class OutputWrapper {
        @InvocableVariable public String result;
    }

    @InvocableMethod(label='Get Nearby Records from Prompt')
    public static List<OutputWrapper> getMapFromPrompt(List<InputWrapper> inputs) {
        InputWrapper input = inputs[0];
        System.debug('QQQ'+inputs)
        if (String.isBlank(input.userPrompt) || String.isBlank(input.recordId)) {
            return wrap('❌ Missing prompt or recordId.');
        }


        String prompt = input.userPrompt.toLowerCase();
        String recordId = input.recordId;
        String prefix = recordId.left(3);

        // Extract object to query
        String objectToQuery;
        if (prompt.contains('lead')) {
            objectToQuery = 'Lead';
        } else if (prompt.contains('property')) {
            objectToQuery = 'Property__c';
        } else {
            return wrap('❌ Could not determine what to search (lead/property) from prompt.');
        }

        // Extract radius (e.g., "within 10 miles")
        Pattern p = Pattern.compile('(\\d+\\.?\\d*)\\s*mile');
        Matcher m = p.matcher(prompt);
        Decimal radius = 10; // default
        if (m.find()) {
            radius = Decimal.valueOf(m.group(1));
        }

        // Get origin location from recordId
        Decimal lat, lng;
        if (prefix == 'a0A') {
            Property__c rec = [SELECT Latitude__c, Longitude__c FROM Property__c WHERE Id = :recordId LIMIT 1];
            lat = rec.Latitude__c;
            lng = rec.Longitude__c;
        } else if (prefix == '00Q') {
            Lead rec = [SELECT Property_Latitude__c, Property_Longitude__c FROM Lead WHERE Id = :recordId LIMIT 1];
            lat = rec.Property_Latitude__c;
            lng = rec.Property_Longitude__c;
        } else {
            return wrap('❌ Unsupported recordId prefix.');
        }

        if (lat == null || lng == null) {
            return wrap('❌ Current record has no valid coordinates.');
        }

        // Query records of the intended object
        List<Map<String, Object>> markers = queryNearby(objectToQuery, recordId, lat, lng, radius, 20);

        String encoded = EncodingUtil.urlEncode(JSON.serialize(markers), 'UTF-8');
        String url = 'https://tanishdragonemperor.github.io/property-map/map.html?lat=' + lat + '&lng=' + lng + '&markers=' + encoded;

        return wrap('✅ View map: ' + url);
    }

    private static List<Map<String, Object>> queryNearby(String objectName, String excludeId, Decimal lat, Decimal lng, Decimal radius, Integer limit) {
        List<Map<String, Object>> markers = new List<Map<String, Object>>();
        List<String> colors = new List<String>{'red','blue','green','orange','purple','yellow','black','brown','cyan','pink'};
        Integer count = 0;
        Integer i = 0;

        if (objectName == 'Property__c') {
            List<Property__c> props = [
                SELECT Name, Latitude__c, Longitude__c 
                FROM Property__c 
                WHERE Id != :excludeId AND Latitude__c != null AND Longitude__c != null
            ];
            for (Property__c p : props) {
                if (haversine(lat, lng, p.Latitude__c, p.Longitude__c) <= radius) {
                    markers.add(new Map<String, Object>{
                        'name' => p.Name,
                        'lat' => p.Latitude__c,
                        'lng' => p.Longitude__c,
                        'color' => colors[Math.mod(i++, colors.size())]
                    });
                    if (++count >= limit) break;
                }
            }

        } else if (objectName == 'Lead') {
            List<Lead> leads = [
                SELECT Name, Property_Latitude__c, Property_Longitude__c 
                FROM Lead 
                WHERE Id != :excludeId AND Property_Latitude__c != null AND Property_Longitude__c != null
            ];
            for (Lead l : leads) {
                if (haversine(lat, lng, l.Property_Latitude__c, l.Property_Longitude__c) <= radius) {
                    markers.add(new Map<String, Object>{
                        'name' => l.Name,
                        'lat' => l.Property_Latitude__c,
                        'lng' => l.Property_Longitude__c,
                        'color' => colors[Math.mod(i++, colors.size())]
                    });
                    if (++count >= limit) break;
                }
            }
        }

        return markers;
    }

    private static Double haversine(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Double R = 3958.8;
        Double dLat = Math.toRadians(lat2 - lat1);
        Double dLon = Math.toRadians(lon2 - lon1);
        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                   Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                   Math.sin(dLon / 2) * Math.sin(dLon / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    private static List<OutputWrapper> wrap(String result) {
        OutputWrapper o = new OutputWrapper();
        o.result = result;
        return new List<OutputWrapper>{ o };
    }
}

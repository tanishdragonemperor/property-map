// Create the input wrapper
NearbyPropertyMapService.InputWrapper input = new NearbyPropertyMapService.InputWrapper();
input.userPrompt = '34.0016,-118.3982 within 10 miles'; // Replace with any lat/lng

// Wrap it into a list
List<NearbyPropertyMapService.InputWrapper> inputList = new List<NearbyPropertyMapService.InputWrapper>{ input };

// Call the Apex method
List<NearbyPropertyMapService.ResponseWrapper> outputList = NearbyPropertyMapService.getMapFromPrompt(inputList);

// Print the result
System.debug('🔗 Map Link Result: ' + outputList[0].result);



This Apex does:

Get record type from prefix

Fetch lat/lng from current record

Get all other records of the same type

Use Haversine to filter those within the radius

Return a dynamic map URL with color-coded markers




public with sharing class NearbyMapApexHandler {
    public class NearbyInput {
        @InvocableVariable public String recordId;
        @InvocableVariable public Decimal radius;
    }

    public class NearbyOutput {
        @InvocableVariable public String mapUrl;
    }

    @InvocableMethod(label='Build Nearby Map from Record')
    public static List<NearbyOutput> getMap(List<NearbyInput> inputList) {
        NearbyInput input = inputList[0];
        String prefix = input.recordId.left(3);
        Decimal lat, lng;
        List<SObject> matches = new List<SObject>();

        if (prefix == 'a0A') {
            Property__c current = [SELECT Latitude__c, Longitude__c FROM Property__c WHERE Id = :input.recordId LIMIT 1];
            lat = current.Latitude__c;
            lng = current.Longitude__c;

            for (Property__c p : [SELECT Name, Latitude__c, Longitude__c FROM Property__c WHERE Id != :input.recordId AND Latitude__c != null AND Longitude__c != null]) {
                if (haversine(lat, lng, p.Latitude__c, p.Longitude__c) <= input.radius) {
                    matches.add(p);
                }
            }
        } else if (prefix == '00Q') {
            Lead current = [SELECT Latitude__c, Longitude__c FROM Lead WHERE Id = :input.recordId LIMIT 1];
            lat = current.Latitude__c;
            lng = current.Longitude__c;

            for (Lead l : [SELECT Name, Latitude__c, Longitude__c FROM Lead WHERE Id != :input.recordId AND Latitude__c != null AND Longitude__c != null]) {
                if (haversine(lat, lng, l.Latitude__c, l.Longitude__c) <= input.radius) {
                    matches.add(l);
                }
            }
        }

        // Build marker data
        List<Map<String, Object>> markerList = new List<Map<String, Object>>();
        List<String> colors = new List<String>{'red','blue','green','orange','purple','yellow','black','brown','cyan','pink'};
        Integer i = 0;

        for (SObject s : matches) {
            Decimal ml = (Decimal)s.get('Latitude__c');
            Decimal mg = (Decimal)s.get('Longitude__c');
            String name = (String)s.get('Name');
            String color = colors[Math.mod(i++, colors.size())];

            markerList.add(new Map<String, Object>{
                'name' => name,
                'lat' => ml,
                'lng' => mg,
                'color' => color
            });
        }

        String encoded = EncodingUtil.urlEncode(JSON.serialize(markerList), 'UTF-8');
        String url = 'https://tanishdragonemperor.github.io/property-map/map.html?lat=' + lat + '&lng=' + lng + '&markers=' + encoded;

        NearbyOutput out = new NearbyOutput();
        out.mapUrl = url;
        return new List<NearbyOutput>{ out };
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
}







List<NearbyMapApexHandler.NearbyInput> inputs = new List<NearbyMapApexHandler.NearbyInput>();

NearbyMapApexHandler.NearbyInput input = new NearbyMapApexHandler.NearbyInput();
input.recordId = 'RECORD_ID_HERE'; // <-- Replace with actual ID
input.radius = 10; // radius in miles

inputs.add(input);

// Call the method
List<NearbyMapApexHandler.NearbyOutput> output = NearbyMapApexHandler.getMap(inputs);

// Print result in the log
System.debug('Map URL: ' + output[0].mapUrl);

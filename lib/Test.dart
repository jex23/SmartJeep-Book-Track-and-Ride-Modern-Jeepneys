import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';

class Test extends StatelessWidget {
  Future<String> _getAddress(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      final place = placemarks[0];
      return '${place.street}, ${place.subLocality}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
    } catch (e) {
      print("Error getting address: $e");
      return "Unknown address";
    }
  }

  Future<void> _updateStatus(String documentId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('Pick_Me_Up').doc(documentId).update({
        'status': newStatus,
      });
    } catch (e) {
      print("Error updating status: $e");
    }
  }
////
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pick Me Up List'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Pick_Me_Up').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final documents = snapshot.data!.docs;

          return ListView.builder(
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final document = documents[index];
              final documentId = document.id;
              final fullName = document['fullName'] as String;
              final geopoint = document['coordinates'] as GeoPoint;
              final passengerType = document['passengerType'] as String;
              final status = document['status'] as String;
              final timestamp = (document['timestamp'] as Timestamp).toDate();
              final latitude = geopoint.latitude;
              final longitude = geopoint.longitude;

              return FutureBuilder<String>(
                future: _getAddress(latitude, longitude),
                builder: (context, addressSnapshot) {
                  if (!addressSnapshot.hasData) {
                    return ListTile(
                      title: Text(fullName),
                      subtitle: Text('Fetching address...'),
                      contentPadding: EdgeInsets.all(16),
                    );
                  }

                  final address = addressSnapshot.data!;

                  return Card(
                    elevation: 5,
                    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(16),
                      title: Text(
                        fullName,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Passenger Type: $passengerType',
                            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                          ),
                          Text(
                            'Status: $status',
                            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                          ),
                          Text(
                            'Address: $address',
                            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Timestamp: ${timestamp.toLocal()}',
                            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              _updateStatus(documentId, 'Accepted');
                            },
                            child: Text('Accept', style: TextStyle(color: Colors.green)),
                          ),
                          TextButton(
                            onPressed: () {
                              _updateStatus(documentId, 'Declined');
                            },
                            child: Text('Decline', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

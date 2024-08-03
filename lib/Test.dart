import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class Test extends StatefulWidget {
  @override
  _TestState createState() => _TestState();
}

class _TestState extends State<Test> {
  int _selectedIndex = 0;
  List<bool> _seatSelected = List.generate(25, (index) => false);
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('Seats');
  late StreamSubscription<DatabaseEvent> _seatDataSubscription;
  Completer<GoogleMapController> _controller = Completer();
  Position? _currentPosition;
  Set<Marker> _markers = Set<Marker>();

  @override
  void initState() {
    super.initState();
    _loadSeatData();
    _getCurrentLocation();
    _loadPickupPoints();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    setState(() {
      _currentPosition = _currentPosition;
    });

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      ),
    );
  }

  Future<void> _loadPickupPoints() async {
    FirebaseFirestore.instance.collection('Pick_Me_Up').snapshots().listen((snapshot) {
      snapshot.docs.forEach((doc) {
        GeoPoint geopoint = doc['coordinates'];
        _markers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(geopoint.latitude, geopoint.longitude),
            infoWindow: InfoWindow(
              title: doc['fullName'],
              snippet: 'Passenger Type: ${doc['passengerType']}',
            ),
          ),
        );
      });
      setState(() {});
    });
  }

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

  void _onSeatTapped(int index) {
    setState(() {
      _seatSelected[index] = !_seatSelected[index];
      String seatPath = 'Seat${index + 1}';
      _databaseRef.child(seatPath).set(_seatSelected[index]);
    });
  }

  void _loadSeatData() {
    _seatDataSubscription = _databaseRef.onValue.listen((DatabaseEvent event) {
      if (!mounted) return; // Check if the widget is still mounted
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _seatSelected = List.generate(25, (index) => data['Seat${index + 1}'] ?? false);
        });
      } else {
        print('No data found in the snapshot.');
      }
    }, onError: (error) {
      print('Error occurred while listening to seat data: $error');
    });
  }

  int get availableSeats => _seatSelected.where((selected) => !selected).length;
  int get occupiedSeats => _seatSelected.where((selected) => selected).length;

  Future<void> _updateStatus(String documentId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('Pick_Me_Up').doc(documentId).update({
        'status': newStatus,
      });
    } catch (e) {
      print("Error updating status: $e");
    }
  }

  Future<void> _deleteDocument(String documentId) async {
    try {
      await FirebaseFirestore.instance.collection('Pick_Me_Up').doc(documentId).delete();
    } catch (e) {
      print("Error deleting document: $e");
    }
  }

  Widget _buildPickUpList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Pick_Me_Up').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs;

        return DraggableScrollableSheet(
          expand: true,
          builder: (context, scrollController) {
            return Container(
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'For Pick Up',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 10),
                      Text(
                        'Available Seats: $availableSeats',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Occupied Seats: $occupiedSeats',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
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
                                    TextButton(
                                      onPressed: () {
                                        _deleteDocument(documentId);
                                      },
                                      child: Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSeats() {
    return Stack(
      children: [
        _buildMap(),
        DraggableScrollableSheet(
          expand: true,
          builder: (context, scrollController) {
            return Container(
              color: Colors.white,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 5,
                          width: 100,
                          margin: EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                    Text("Driver Seat", style: TextStyle(fontSize: 18)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 10),
                        Text(
                          'Available Seats: $availableSeats',
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Occupied Seats: $occupiedSeats',
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    _buildSeatRow([0], "Driver"),
                    SizedBox(height: 20),
                    _buildSeatRow([1, 2, null, null, 3]),
                    SizedBox(height: 20),
                    _buildSeatRow([4, 5, null, null, 6]),
                    SizedBox(height: 20),
                    _buildSeatRow([7, 8, null, null, null, null]),
                    SizedBox(height: 20),
                    _buildSeatRow([9, 10, null, null, 11]),
                    SizedBox(height: 20),
                    _buildSeatRow([12, 13, null, null, 14]),
                    SizedBox(height: 20),
                    _buildSeatRow([15, 16, null, null, 17]),
                    SizedBox(height: 20),
                    _buildSeatRow([18, 19, null, null, 20]),
                    SizedBox(height: 20),
                    _buildSeatRow([21, 22, 23, 24]),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSeatRow(List<int?> seatIndices, [String? label]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(label, style: TextStyle(fontSize: 16)),
          ),
        ...seatIndices.map((index) {
          if (index == null || index >= _seatSelected.length) {
            return SizedBox(width: 30); // Adjust spacing as necessary
          } else {
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: GestureDetector(
                onTap: () => _onSeatTapped(index),
                child: Container(
                  width: 50, // Adjust width as necessary
                  height: 50, // Adjust height as necessary
                  decoration: BoxDecoration(
                    color: _seatSelected[index] ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Center(
                    child: Text(
                      "Seat ${index + 1}",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }).toList(),
      ],
    );
  }

  @override
  void dispose() {
    _seatDataSubscription.cancel(); // Cancel the stream subscription
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pick Me Up List'),
      ),
      body: Stack(
        children: [
          _buildMap(),
          _selectedIndex == 0 ? _buildPickUpList() : _buildSeats(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'For Pick Up',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_seat),
            label: 'Seats',
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return _currentPosition == null
        ? Center(child: CircularProgressIndicator())
        : GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        zoom: 14.0,
      ),
      markers: _markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      onMapCreated: (GoogleMapController controller) {
        _controller.complete(controller);
      },
    );
  }
}

void main() {
  runApp(MaterialApp(
    home: Test(),
  ));
}

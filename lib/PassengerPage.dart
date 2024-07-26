import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart'; // Import Firebase Realtime Database

class PassengerPage extends StatefulWidget {
  @override
  _PassengerPageState createState() => _PassengerPageState();
}

class _PassengerPageState extends State<PassengerPage> {
  late User currentUser;
  DocumentSnapshot? passengerSnapshot;
  Position? currentPosition;
  String? currentAddress;
  late GoogleMapController mapController;
  BitmapDescriptor? customIcon;
  int _selectedIndex = 0; // State variable for BottomNavigationBar
  List<bool> _seatSelected = List.generate(25, (index) => false);
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('Seats');

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _loadCustomMarker();
    currentUser = FirebaseAuth.instance.currentUser!;
    FirebaseFirestore.instance.collection('passengers').doc(currentUser.uid).get().then((snapshot) {
      setState(() {
        passengerSnapshot = snapshot;
      });
    }).catchError((error) {
      print('Error retrieving user data: $error');
    });
    _loadSeatData(); // Load initial seat data from Firebase
  }

  Future<void> _loadCustomMarker() async {
    customIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(1, 1)),
      'Imagess/arm-up.png',
    );
  }

  Future<void> _requestLocationPermission() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else if (status.isDenied) {
      print('Location permission denied');
    } else if (status.isPermanentlyDenied) {
      print('Location permission permanently denied');
      openAppSettings();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        currentPosition = position;
      });
      _getAddressFromLatLng(position);
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];
      setState(() {
        currentAddress = "${place.street}, ${place.locality}, ${place.postalCode}, ${place.country}";
      });
    } catch (e) {
      print('Error getting address: $e');
    }
  }
  //fetch recent Location
  Future<void> _refreshLocation() async {
    await _getCurrentLocation();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _loadSeatData() async {
    _databaseRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _seatSelected = List.generate(25, (index) => data['Seat${index + 1}'] ?? false);
          print('Seats updated: $_seatSelected'); // Debug statement
        });
      }
    });
  }

  Widget _buildMap() {
    return currentPosition != null
        ? GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        zoom: 15.0,
      ),
      markers: {
        Marker(
          markerId: MarkerId('currentLocation'),
          position: LatLng(currentPosition!.latitude, currentPosition!.longitude),
          icon: customIcon ?? BitmapDescriptor.defaultMarker,
        ),
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
    )
        : Center(child: CircularProgressIndicator());
  }

  Widget _buildSeats() {
    return Center(
      child: Column(
        children: [
          Text("Seat Reservation", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 20),
          _buildSeatRow([0], "Driver"),
          SizedBox(height: 20),
          _buildSeatRow([1, 2, null, null,3]),
          SizedBox(height: 20),
          _buildSeatRow([4, 5, null,null, 6]),
          SizedBox(height: 20),
          _buildSeatRow([7, 8, null, null, null, null]),
          SizedBox(height: 20),
          _buildSeatRow([9, 10, null,null, 11]),
          SizedBox(height: 20),
          _buildSeatRow([12, 13, null,null, 14]),
          SizedBox(height: 20),
          _buildSeatRow([15, 16, null,null, 17]),
          SizedBox(height: 20),
          _buildSeatRow([18, 19, null,null, 20]),
          SizedBox(height: 20),
          _buildSeatRow([21, 22, 23, 24]),
        ],
      ),
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
              child: Container(
                width: 50, // Adjust width as necessary
                height: 50, // Adjust height as necessary
                decoration: BoxDecoration(
                  color: _seatSelected[index] ? Colors.green : Colors.grey, // Color based on seat status
                  borderRadius: BorderRadius.circular(8), // Rounded corners
                ),
                child: Center(
                  child: Text(
                    "Seat ${index + 1}",
                    style: TextStyle(
                      color: Colors.white, // Text color
                      fontWeight: FontWeight.bold,
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Passenger Page'),
      ),
      body: _selectedIndex == 0
          ? passengerSnapshot != null
          ? SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Welcome!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
              _buildFullNameRow(
                passengerSnapshot!['firstName'],
                passengerSnapshot!['middleName'],
                passengerSnapshot!['lastName'],
              ),
              _buildAddressRow(passengerSnapshot!['address']),
              _buildDetailRow('Passenger Type', passengerSnapshot!['passengerType']),
              _buildLocationRow(),
              _buildMapContainer(),
            ],
          ),
        ),
      )
          : Center(child: CircularProgressIndicator())
          : _buildSeats(), // Seat reservation view
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_seat),
            label: 'Seats',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildFullNameRow(String firstName, String middleName, String lastName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$firstName $middleName $lastName',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(String address) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              address,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Current Coordinates: ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Expanded(
                child: currentPosition != null
                    ? Text(
                  'Latitude: ${currentPosition!.latitude}, Longitude: ${currentPosition!.longitude}',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[700],
                  ),
                )
                    : Text(
                  'Fetching location...',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          if (currentAddress != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  Text(
                    'Address: ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      currentAddress!,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapContainer() {
    return Container(
      height: 300,
      child: Stack(
        children: [
          _buildMap(),
          Positioned(
            bottom: 10,
            right: 10,
            child: FloatingActionButton(
              onPressed: _refreshLocation,
              child: Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}

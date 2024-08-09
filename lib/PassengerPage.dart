import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'PassengerLoginPage.dart'; // Ensure this file exists and is correctly imported



class PassengerPage extends StatefulWidget {
  @override
  _PassengerPageState createState() => _PassengerPageState();
}

class _PassengerPageState extends State<PassengerPage> {
  late User currentUser;
  DocumentSnapshot? passengerSnapshot;
  Position? currentPosition;
  String? currentAddress;
  String? busAddress;
  late GoogleMapController mapController;
  BitmapDescriptor? customIcon;
  BitmapDescriptor? busIcon; // Added for bus icon
  int _selectedIndex = 0;
  List<bool> _seatSelected = List.generate(25, (index) => false);
  late DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('Bulan/Seats');
  MapType _currentMapType = MapType.hybrid; // Track map type
  StreamSubscription<Position>?
      _positionStreamSubscription; // Stream subscription for location updates
  StreamSubscription<QuerySnapshot>? _pickMeUpStreamSubscription; // Correctly declared
  Set<Marker> _markers = {}; // Set of markers for the map
  bool _shouldFollowUser = true; // Flag to control camera movement
  bool _shouldFollowBus = true; // Flag to control map following bus location
  bool _isClicked = false;
  String _pickMeUpStatus = 'Unknown'; // Initialize with a default value
  // References for bus locations
  final DatabaseReference _bulanBusLocationRef =
  FirebaseDatabase.instance.ref().child('Bus/BulanBus/Location');
  final DatabaseReference _matnogBusLocationRef =
  FirebaseDatabase.instance.ref().child('Bus/MatnogBus/Location');
  String _focusedBus = 'user'; // default to user location
  String _routeText = 'Pick a Bus to Load Route'; // State variable for the floating text
  double _bulanBusLatitude = 0.0;
  double _bulanBusLongitude = 0.0;
  double _matnogBusLatitude = 0.0;
  double _matnogBusLongitude = 0.0;
  late DatabaseReference _activeDatabaseRef;
  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _loadCustomMarker();
    _loadBusIcon(); // Load bus icon
    currentUser = FirebaseAuth.instance.currentUser!;
    FirebaseFirestore.instance
        .collection('passengers')
        .doc(currentUser.uid)
        .get()
        .then((snapshot) {
      setState(() {
        passengerSnapshot = snapshot;
      });
      _startListeningForPickMeUpStatus(); // Start listening for real-time updates
    }).catchError((error) {
      print('Error retrieving user data: $error');
    });
    _loadSeatData();
    _loadBusLocations(); // Load bus locations for both buses

    // Set default to User Location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onLocationOptionSelected('user'); // Ensure user location is selected on initialization
    });
  }
  @override
  void dispose() {
    _pickMeUpStreamSubscription?.cancel(); // Cancel the stream subscription
    _positionStreamSubscription?.cancel(); // Also cancel location updates
    super.dispose();
  }
  Future<void> _loadCustomMarker() async {
    customIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(1, 1)),
      'Imagess/arm-up.png', // Ensure this path is correct
    );
  }
  Future<void> _loadBusIcon() async {
    busIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(1, 1)),
      'Imagess/bus2.png', // Ensure this path is correct
    );
  }
  Future<void> _getPickMeUpStatus() async {
    if (currentUser != null) {
      try {
        final query = FirebaseFirestore.instance
            .collection('Pick_Me_Up')
            .where('fullName', isEqualTo:
        '${passengerSnapshot!['firstName']} ${passengerSnapshot!['middleName']} ${passengerSnapshot!['lastName']}')
            .where('status', isEqualTo: 'waiting');

        final snapshot = await query.get();

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          setState(() {
            _pickMeUpStatus = doc['status'] ?? 'Unknown'; // Retrieve the status field
          });
        } else {
          setState(() {
            _pickMeUpStatus = 'No request found'; // Handle case where no document matches
          });
        }
      } catch (error) {
        print('Failed to get Pick Me Up status: $error');
      }
    }
  }
  void _startListeningForPickMeUpStatus() {
    final query = FirebaseFirestore.instance
        .collection('Pick_Me_Up')
        .where('fullName', isEqualTo:
    '${passengerSnapshot!['firstName']} ${passengerSnapshot!['middleName']} ${passengerSnapshot!['lastName']}');

    _pickMeUpStreamSubscription = query.snapshots().listen((QuerySnapshot snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final status = doc['status'] ?? 'Unknown';

        setState(() {
          _pickMeUpStatus = status;

          // Toggle the button if the status is 'Declined'
          if (status == 'Declined') {
            _isClicked = false; // Set the button to 'Pick Me Up' state
            _deletePickMeUpRequest(doc.id); // Call the delete method
          }
        });
      } else {
        setState(() {
          _pickMeUpStatus = 'No request found';
          _isClicked = false; // Reset button if no request is found
        });
      }
    });
  }
  Future<void> _deletePickMeUpRequest(String documentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('Pick_Me_Up')
          .doc(documentId)
          .delete();
      print('Pick Me Up request deleted successfully');
    } catch (error) {
      print('Failed to delete Pick Me Up request: $error');
    }
  }
  // Method to update the database reference path
  void _updateDatabaseRef(String bus) {
    setState(() {
      _databaseRef = FirebaseDatabase.instance.ref().child('$bus/Seats');
      _activeDatabaseRef = _databaseRef; // Set the active reference
      _loadSeatData(); // Reload seat data for the newly selected bus
    });
  }

  void _toggleButton() {
    setState(() {
      if (_isClicked) {
        _cancelRequest();
      } else {
        _sendPickMeUpRequest();
      }
      _isClicked = !_isClicked;
    });
  }
  Future<void> _sendPickMeUpRequest() async {
    if (currentPosition != null && passengerSnapshot != null) {
      try {
        await FirebaseFirestore.instance.collection('Pick_Me_Up').add({
          'coordinates': GeoPoint(currentPosition!.latitude, currentPosition!.longitude),
          'fullName': '${passengerSnapshot!['firstName']} ${passengerSnapshot!['middleName']} ${passengerSnapshot!['lastName']}',
          'passengerType': passengerSnapshot!['passengerType'],
          'status': 'waiting', // Added status field
          'timestamp': FieldValue.serverTimestamp(),
        });
        print('Pick Me Up request sent successfully');
      } catch (error) {
        print('Failed to send Pick Me Up request: $error');
      }
    }
  }
  Future<void> _requestLocationPermission() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      _startLocationUpdates();
    } else if (status.isDenied) {
      print('Location permission denied');
    } else if (status.isPermanentlyDenied) {
      print('Location permission permanently denied');
      openAppSettings();
    }
  }
  void _startLocationUpdates() {
    _positionStreamSubscription = Geolocator.getPositionStream(
            // Optionally use Geolocator.getPositionStream() with named parameters if supported
            // Geolocator.getPositionStream(desiredAccuracy: LocationAccuracy.high, distanceFilter: 10)
            )
        .listen((Position position) {
      _updateLocation(position);
    });
  }
  Future<void> _updateLocation(Position position) async {
    setState(() {
      currentPosition = position;

      // Update or add the user's current location marker
      _markers.removeWhere((marker) => marker.markerId.value == 'currentLocation');
      _markers.add(
        Marker(
          markerId: MarkerId('currentLocation'),
          position: LatLng(position.latitude, position.longitude),
          icon: customIcon ?? BitmapDescriptor.defaultMarker,
        ),
      );
    });

    _getAddressFromLatLng(position);

    if (_shouldFollowUser && mapController != null) {
      mapController.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    }
  }
  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];
      setState(() {
        currentAddress =
            "${place.street}, ${place.locality}, ${place.postalCode}, ${place.country}";
      });
    } catch (e) {
      print('Error getting address: $e');
    }
  }
  Future<void> _refreshLocation() async {
    if (currentPosition != null) {
      await _updateLocation(currentPosition!);
    }
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
      if (_databaseRef == _activeDatabaseRef) { // Check if the reference is active
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          setState(() {
            _seatSelected =
                List.generate(25, (index) => data['Seat${index + 1}'] ?? false);
            print('Seats updated: $_seatSelected');
          });
        }
      }
    });
  }
  Future<void> _loadBusLocations() async {
    _loadBulanBusLocation(); // Start listening for Bulan Bus updates
    _loadMatnogBusLocation(); // Start listening for Matnog Bus updates
  }
  void _loadBulanBusLocation() {
    _bulanBusLocationRef.onValue.listen((DatabaseEvent event) async {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        _bulanBusLatitude = data['latitude'];
        _bulanBusLongitude = data['longitude'];
        _updateBulanBusLocation(_bulanBusLatitude, _bulanBusLongitude);

        if (_focusedBus == 'bulanBus') {
          _getBusAddressFromLatLng(_bulanBusLatitude, _bulanBusLongitude, 'Bulan');
          // Load the route text from Firebase for Bulan Bus
          // _routeText = (await FirebaseDatabase.instance.ref().child('/Bus/BulanBus/Route').get()).value.toString();
          // _updateDatabaseRef('Matnog'); // Update the seats reference to Matnog when Matnog bus is clicked
        }

        if (_shouldFollowBus) {
          _followBusMovement(_bulanBusLatitude, _bulanBusLongitude);
        }
      }
    });
  }
  void _loadMatnogBusLocation() {
    _matnogBusLocationRef.onValue.listen((DatabaseEvent event) async {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        _matnogBusLatitude = data['latitude'];
        _matnogBusLongitude = data['longitude'];
        _updateMatnogBusLocation(_matnogBusLatitude, _matnogBusLongitude);

        if (_focusedBus == 'matnogBus') {
          _getBusAddressFromLatLng(_matnogBusLatitude, _matnogBusLongitude, 'Matnog');
          // Load the route text from Firebase for Matnog Bus
          // _routeText = (await FirebaseDatabase.instance.ref().child('/Bus/MatnogBus/Route').get()).value.toString();
        }

        if (_shouldFollowBus) {
          _followBusMovement(_matnogBusLatitude, _matnogBusLongitude);
        }
      }
    });
  }
  void _followBusMovement(double latitude, double longitude) {
    if (mapController != null) {
      // Only move the camera if the bus is currently selected for focus
      if (_focusedBus == 'user' || (_focusedBus == 'bulanBus' && latitude == _bulanBusLatitude && longitude == _bulanBusLongitude) || (_focusedBus == 'matnogBus' && latitude == _matnogBusLatitude && longitude == _matnogBusLongitude)) {
        mapController.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(latitude, longitude),
          ),
        );
      }
    }
  }
  void _updateBulanBusLocation(double latitude, double longitude) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == 'bulanBus');
      _markers.add(
        Marker(
          markerId: MarkerId('bulanBus'),
          position: LatLng(latitude, longitude),
          icon: busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });

    // Only follow Bulan Bus if it's the currently focused bus
    if (_focusedBus == 'bulanBus') {
      _followBusMovement(latitude, longitude);
    }
  }

  void _updateMatnogBusLocation(double latitude, double longitude) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == 'matnogBus');
      _markers.add(
        Marker(
          markerId: MarkerId('matnogBus'),
          position: LatLng(latitude, longitude),
          icon: busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });

    // Only follow Matnog Bus if it's the currently focused bus
    if (_focusedBus == 'matnogBus') {
      _followBusMovement(latitude, longitude);
    }
  }
  Future<void> _cancelRequest() async {
    if (currentPosition != null && passengerSnapshot != null) {
      try {
        final query = FirebaseFirestore.instance
            .collection('Pick_Me_Up')
            .where('fullName', isEqualTo:
        '${passengerSnapshot!['firstName']} ${passengerSnapshot!['middleName']} ${passengerSnapshot!['lastName']}')
            .where('status', isEqualTo: 'waiting');

        final snapshot = await query.get();

        for (var doc in snapshot.docs) {
          await FirebaseFirestore.instance
              .collection('Pick_Me_Up')
              .doc(doc.id)
              .delete();
        }

        print('Pick Me Up request canceled successfully');
      } catch (error) {
        print('Failed to cancel Pick Me Up request: $error');
      }
    }
  }
  Future<void> _getBusAddressFromLatLng(
      double latitude, double longitude, String busLocation) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      Placemark place = placemarks[0];
      setState(() {
        busAddress = "$busLocation Bus Address: ${place.street}, ${place.locality}, ${place.postalCode}, ${place.country}";
      });
    } catch (e) {
      print('Error getting bus address: $e');
    }
  }
  int getOccupiedSeatsCount() {
    return _seatSelected.where((seat) => seat).length;
  }

  int getAvailableSeatsCount() {
    return _seatSelected.length - getOccupiedSeatsCount();
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Logout'),
          content: Text('Are you sure you want to logout?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
            ),
            TextButton(
              child: Text('Logout'),
              onPressed: () async {
                // Clear any necessary data or state here

                Navigator.of(context).pop(); // Close the dialog

                // Navigate to PassengerLoginPage and clear the navigation stack
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => PassengerLoginPage()),
                  // Changed to PassengerLoginPage
                  (route) => false,
                );
              },
            ),
          ],
        );
      },
    );
  }
  void _onMapTypeChanged(MapType mapType) {
    setState(() {
      _currentMapType = mapType;
    });
  }

  void _onLocationOptionSelected(String value) {
    setState(() {
      if (value == 'user') {
        _shouldFollowBus = false;
        _shouldFollowUser = true;
        _focusedBus = 'user'; // Set focus to user location
        if (currentPosition != null && mapController != null) {
          mapController.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(currentPosition!.latitude, currentPosition!.longitude),
            ),
          );
        }
        busAddress = null; // Clear bus address since user is focused
      } else if (value == 'bulanBus') {
        _shouldFollowUser = false;
        _shouldFollowBus = true;
        _focusedBus = 'bulanBus'; // Set focus to Bulan Bus
        _getBusAddressFromLatLng(_bulanBusLatitude, _bulanBusLongitude, 'Bulan');
        _routeText = 'Loading route...'; // Indicate that the route is being fetched

        // Fetch route from Firebase and update route text
        FirebaseDatabase.instance.ref().child('/Bus/BulanBus/Route').get().then((snapshot) {
          setState(() {
            _routeText = snapshot.value.toString();
          });
        }).catchError((error) {
          setState(() {
            _routeText = 'Failed to load route';
          });
          print('Error fetching route: $error');
        });

        // Animate camera to Bulan Bus location
        if (mapController != null) {
          mapController.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(_bulanBusLatitude, _bulanBusLongitude),
            ),
          );
        }
      } else if (value == 'matnogBus') {
        _shouldFollowUser = false;
        _shouldFollowBus = true;
        _focusedBus = 'matnogBus'; // Set focus to Matnog Bus
        _getBusAddressFromLatLng(_matnogBusLatitude, _matnogBusLongitude, 'Matnog');
        _routeText = 'Loading route...'; // Indicate that the route is being fetched

        // Fetch route from Firebase and update route text
        FirebaseDatabase.instance.ref().child('/Bus/MatnogBus/Route').get().then((snapshot) {
          setState(() {
            _routeText = snapshot.value.toString();
          });
        }).catchError((error) {
          setState(() {
            _routeText = 'Failed to load route';
          });
          print('Error fetching route: $error');
        });

        // Animate camera to Matnog Bus location
        if (mapController != null) {
          mapController.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(_matnogBusLatitude, _matnogBusLongitude),
            ),
          );
        }
      }
    });
  }


  Widget _buildMap() {
    return GoogleMap(
      onMapCreated: _onMapCreated,
      markers: _markers,
      initialCameraPosition: CameraPosition(
        target: currentPosition != null
            ? LatLng(currentPosition!.latitude, currentPosition!.longitude)
            : LatLng(0, 0),
        zoom: 14.0,
      ),
      mapType: _currentMapType,
    );
  }
  @override
  Widget build(BuildContext context) {
    final passengerSnapshot =
        this.passengerSnapshot; // To use in the build method

    return Scaffold(
      appBar: AppBar(
        title: Text('Passenger'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _showLogoutDialog,
          ),PopupMenuButton<String>(
            icon: Icon(Icons.location_searching),
            onSelected: (value) {
              _onLocationOptionSelected(value);
              // Update database reference based on bus selection
              if (value == 'matnogBus') {
                _updateDatabaseRef('Matnog');
              } else if (value == 'bulanBus') {
                _updateDatabaseRef('Bulan');
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'user',
                  child: Text('User Location'),
                ),
                PopupMenuItem<String>(
                  value: 'bulanBus',
                  child: Text('Bulan Bus Location'),
                ),
                PopupMenuItem<String>(
                  value: 'matnogBus',
                  child: Text('Matnog Bus Location'),
                ),
              ];
            },
          ),
          PopupMenuButton<MapType>(
            icon: Icon(Icons.map),
            onSelected: _onMapTypeChanged,
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<MapType>(
                  value: MapType.normal,
                  child: Text('Normal'),
                ),
                PopupMenuItem<MapType>(
                  value: MapType.satellite,
                  child: Text('Satellite'),
                ),
                PopupMenuItem<MapType>(
                  value: MapType.hybrid,
                  child: Text('Hybrid'),
                ),
                PopupMenuItem<MapType>(
                  value: MapType.terrain,
                  child: Text('Terrain'),
                ),
              ];
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(),
          Positioned(
            top: 20.0,
            left: 50.0,
            right: 50.0,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 5.0),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Text(
                _routeText, // Display the route text
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.1,
            maxChildSize: 1.0,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, 255, 255, 255),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_selectedIndex == 0 && passengerSnapshot != null) ...[
                        Padding(
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
                              _buildDetailRow('Passenger Type',
                                  passengerSnapshot!['passengerType']),
                              _buildLocationRow(),
                              Center(
                                child: Text('Bus Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                              ),
                              _buildBusLocationRow(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Available Seats: ${getAvailableSeatsCount()}',style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),),
                                  SizedBox(width: 10,),
                                  Text('Occupied Seats: ${getOccupiedSeatsCount()}',style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,color: Colors.red),),
                                ],
                              ),
                              Center(
                                child: Text(
                                  _isClicked ? '' : 'Click to be Pick Up',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _isClicked ? Colors.green : Colors.black, // Change text color if needed
                                  ),
                                ),
                              ),
                              Center(
                                child: ElevatedButton(

                                  onPressed: _toggleButton,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isClicked
                                        ? Colors.green
                                        : Colors.white, // Background color
                                    foregroundColor: _isClicked
                                        ? Colors.white
                                        : Colors.green, // Text color
                                    side: BorderSide(
                                      color: Colors.green, // Outline color
                                      width: 2.0, // Outline width
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                  ),
                                  child: Text(
                                    _isClicked ? 'Cancel' : 'Pick Me Up',),

                                ),
                              ),
                              Center(
                                child: Text(
                                  'Status: $_pickMeUpStatus',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_selectedIndex == 1) _buildSeats(),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.info),
            label: 'Details',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_seat),
            label: 'Seats',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blueAccent,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildFullNameRow(
      String firstName, String middleName, String lastName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.person, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text(
            '$firstName $middleName $lastName',
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(String address) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.location_on, color: Colors.blueAccent),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              address,
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String title, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.info, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text(
            '$title: $detail',
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.my_location, color: Colors.blueAccent),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              currentAddress ?? 'Loading...',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusLocationRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.directions_bus, color: Colors.blueAccent),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              busAddress ?? 'Loading...',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeats() {
    int occupiedSeats = _seatSelected.where((seat) => seat).length;
    int availableSeats = _seatSelected.length - occupiedSeats;

    return Center(
      child: Column(
        children: [
          Text("Seat Details",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(
            "Available Seats: $availableSeats",
            style: TextStyle(fontSize: 18, color: Colors.green),
          ),
          Text(
            "Occupied Seats: $occupiedSeats",
            style: TextStyle(fontSize: 18, color: Colors.red),
          ),
          SizedBox(height: 20),
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
            return SizedBox(width: 30);
          } else {
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _seatSelected[index] ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(8),
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
            );
          }
        }).toList(),
      ],
    );
  }
}

class RestaurantModel {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverImageUrl;
  final String address;
  final double latitude;
  final double longitude;
  final String? category;
  final double averageRating;

  const RestaurantModel(
      {required this.id,
      required this.name,
      this.description,
      this.logoUrl,
      this.coverImageUrl,
      required this.address,
      required this.latitude,
      required this.longitude,
      this.category,
      required this.averageRating});

  factory RestaurantModel.fromJson(Map<String, dynamic> json) =>
      RestaurantModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        logoUrl: json['logo_url'] as String?,
        coverImageUrl: json['cover_image_url'] as String?,
        address: json['address'] as String,
        latitude: double.parse(json['latitude'].toString()),
        longitude: double.parse(json['longitude'].toString()),
        category: json['category'] as String?,
        averageRating: double.parse((json['average_rating'] ?? 0).toString()),
      );
}

class MenuItemModel {
  final String id;
  final String restaurantId;
  final String name;
  final String? description;
  final double price;
  final String? category;
  final String imageUrl;
  final bool available;

  const MenuItemModel(
      {required this.id,
      required this.restaurantId,
      required this.name,
      this.description,
      required this.price,
      this.category,
      required this.imageUrl,
      required this.available});

  factory MenuItemModel.fromJson(Map<String, dynamic> json) => MenuItemModel(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: double.parse(json['price'].toString()),
        category: json['category'] as String?,
        imageUrl: json['image_url'] as String,
        available: json['available'] as bool? ?? true,
      );
}

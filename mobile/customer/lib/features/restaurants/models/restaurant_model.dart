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
  final bool isOpen;
  final Map<String, dynamic>? operatingHours;

  const RestaurantModel({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.coverImageUrl,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.category,
    required this.averageRating,
    this.isOpen = true,
    this.operatingHours,
  });

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
        isOpen: (json['is_open'] as bool?) ?? true,
        operatingHours: json['operating_hours'] as Map<String, dynamic>?,
      );
}

class ModifierOption {
  final String name;
  final double price;

  const ModifierOption({required this.name, required this.price});

  factory ModifierOption.fromJson(Map<String, dynamic> json) => ModifierOption(
        name: json['name'] as String,
        price: double.parse((json['price'] ?? 0).toString()),
      );

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

class ModifierGroup {
  final String name;
  final String type; // 'single' or 'multi'
  final bool required;
  final List<ModifierOption> options;

  const ModifierGroup({
    required this.name,
    required this.type,
    required this.required,
    required this.options,
  });

  factory ModifierGroup.fromJson(Map<String, dynamic> json) => ModifierGroup(
        name: json['name'] as String,
        type: json['type'] as String? ?? 'single',
        required: json['required'] as bool? ?? false,
        options: (json['options'] as List<dynamic>? ?? [])
            .map((e) => ModifierOption.fromJson(e as Map<String, dynamic>))
            .toList(),
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
  final List<ModifierGroup> modifiers;

  const MenuItemModel({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.description,
    required this.price,
    this.category,
    required this.imageUrl,
    required this.available,
    this.modifiers = const [],
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) => MenuItemModel(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: double.parse(json['price'].toString()),
        category: json['category'] as String?,
        imageUrl: json['image_url'] as String,
        available: json['available'] as bool? ?? true,
        modifiers: (json['modifiers'] as List<dynamic>? ?? [])
            .map((e) => ModifierGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

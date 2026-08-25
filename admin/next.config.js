/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    // Allow external image domains used by the platform.
    // Cloudinary is used for restaurant logos, cover photos, menu item images,
    // and user profile photos. The wildcard pattern covers all Cloudinary
    // subdomains (res.cloudinary.com) and any custom domains you may configure.
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'res.cloudinary.com',
        pathname: '/**',
      },
      {
        // Catch-all for any other CDN or storage URL that may appear in
        // profile_photo_url, logo_url, or cover_image_url fields.
        protocol: 'https',
        hostname: '**',
      },
    ],
  },
};

module.exports = nextConfig;

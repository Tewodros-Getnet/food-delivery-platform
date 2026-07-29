import { v2 as cloudinary } from 'cloudinary';
import { env } from '../config/env';

cloudinary.config({
  cloud_name: env.CLOUDINARY_CLOUD_NAME,
  api_key: env.CLOUDINARY_API_KEY,
  api_secret: env.CLOUDINARY_API_SECRET,
});

export async function uploadImage(
  base64Data: string,
  folder: string
): Promise<string> {
  try {
    // Ensure the base64 string has the data URI prefix Cloudinary expects
    const dataUri = base64Data.startsWith('data:')
      ? base64Data
      : `data:image/jpeg;base64,${base64Data}`;
    const result = await cloudinary.uploader.upload(dataUri, { folder });
    return result.secure_url;
  } catch (err: unknown) {
    const detail = err && typeof err === 'object' ? JSON.stringify(err) : String(err);
    throw new Error(`Cloudinary error: ${detail}`);
  }
}

export async function deleteImage(publicId: string): Promise<void> {
  await cloudinary.uploader.destroy(publicId);
}

import { Camera, CameraResultType, CameraSource } from '@capacitor/camera';
import { Capacitor } from '@capacitor/core';

function CameraCaptureInput({
  hidden,
  disabled = false,
  supportedMimeTypes,
  setMediaAttachments,
}) {
  const isNative = Capacitor.isNativePlatform();

  const handleCapture = async () => {
    if (!isNative) {
      // Fallback for web - use file input
      return;
    }

    try {
      const image = await Camera.getPhoto({
        quality: 90,
        allowEditing: false,
        resultType: CameraResultType.Uri,
        source: CameraSource.Camera,
      });

      // Convert to blob for upload
      const response = await fetch(image.webPath);
      const blob = await response.blob();
      const file = new File([blob], `photo_${Date.now()}.${image.format}`, {
        type: `image/${image.format}`,
      });

      setMediaAttachments((attachments) => [
        ...attachments,
        {
          file: file,
          type: file.type,
          size: file.size,
          url: image.webPath,
          id: null, // indicate uploaded state
          description: null,
        },
      ]);
    } catch (error) {
      // User cancelled or permission denied
      console.error('Camera error:', error);
    }
  };

  // For native platforms, use a button trigger
  if (isNative) {
    return (
      <button
        type="button"
        hidden={hidden}
        disabled={disabled}
        onClick={handleCapture}
        style={{ display: 'none' }}
      />
    );
  }

  // Fallback for web - use file input
  const filteredSupportedMimeTypes = supportedMimeTypes?.filter((mimeType) =>
    /^image\//i.test(mimeType)
  );

  return (
    <input
      type="file"
      hidden={hidden}
      accept={filteredSupportedMimeTypes?.join(',')}
      capture="environment"
      disabled={disabled}
      onChange={(e) => {
        const files = e.target.files;
        if (!files) return;
        const mediaFile = Array.from(files)[0];
        if (!mediaFile) return;
        setMediaAttachments((attachments) => [
          ...attachments,
          {
            file: mediaFile,
            type: mediaFile.type,
            size: mediaFile.size,
            url: URL.createObjectURL(mediaFile),
            id: null, // indicate uploaded state
            description: null,
          },
        ]);
        e.target.value = null;
      }}
    />
  );
}

export const supportsCameraCapture = (() => {
  // Check if running on native platform or web with capture support
  if (Capacitor.isNativePlatform()) {
    return true;
  }
  const input = document.createElement('input');
  return 'capture' in input;
})();

export default CameraCaptureInput;

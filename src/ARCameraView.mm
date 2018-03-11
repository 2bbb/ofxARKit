

#include "ARCameraView.h"

namespace ARCore {

    ARCameraView::ARCameraView(ARSession * session, bool mUseFbo):
    mUseFbo(mUseFbo),
    near(1.0),
    far(1000.0){

        // Store session.
        this->session = session;    

        // Get the resolution we're capturing at.
        auto dimensions = session.currentFrame.camera.imageResolution;
        
        
        // set camera frame dimensions.
        mCameraFrameDimensions.x = dimensions.width;
        mCameraFrameDimensions.y = dimensions.height;
        
        auto resolution = ARUtils::getDeviceDimensions(true);
        mResolution = CGSizeMake(resolution.x,resolution.y);

        // setup other variables with defaults.
        ambientIntensity = 0.0;
        orientation = [[UIApplication sharedApplication] statusBarOrientation];
        yTexture = NULL;
        CbCrTexture = NULL;
        near = 0.1;
        far = 1000.0;
        mDebugMode = false;
        xShift = 0;
        yShift = 0;

        
        // initialize video texture cache
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, ofxiOSGetGLView().context, NULL, &_videoTextureCache);
        if (err){
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        }

        // build fbo if needed
        if(mUseFbo){
            buildFBO();
        }
        
        
        // initialize drawing mesh.
        vMesh.setVertexData(kImagePlaneVertexData, 4, 16, GL_DYNAMIC_DRAW);
        cameraConvertShader.setupShaderFromSource(GL_VERTEX_SHADER, ARShaders::camera_convert_vertex);
        cameraConvertShader.setupShaderFromSource(GL_FRAGMENT_SHADER, ARShaders::camera_convert_fragment);
        cameraConvertShader.linkProgram();

    }


    void ARCameraView::update(){
        // if we haven't set a session - just stop things here.
        if(!session){
            return;
        }
        
        // update tracking state
        trackingState = session.currentFrame.camera.trackingState;
        
        
        // update camera transform
        cameraMatrices.cameraTransform = ARUtils::toMat4(session.currentFrame.camera.transform);
        
        // update camera projection and view matrices.
        getMatricesForOrientation(orientation,near,far);
        
        if(session.currentFrame){
            // update texture coordinates
            updatePlaneTexCoords();
            
            // do light estimates
            if (session.currentFrame.lightEstimate) {
                
                // note - in lumens, divide by 1000 to get a more normal value
                ambientIntensity = session.currentFrame.lightEstimate.ambientIntensity / 1000;
                
                // note - in kelvin,
                //A value of 6500 represents neutral (pure white) lighting; lower values indicate a "warmer" yellow or orange tint, and higher values indicate a "cooler" blue tint.
                ambientColorTemperature = session.currentFrame.lightEstimate.ambientColorTemperature;
            }
            
            // grab current frame pixels from camera
            CVPixelBufferRef pixelBuffer = session.currentFrame.capturedImage;
            
            if (CVPixelBufferGetPlaneCount(pixelBuffer) >= 2) {
                
                // build the new camera frame.
                buildCameraFrame(pixelBuffer);
                
                // update fbo if necessary.
                updateFBO();
            }
            
        }
        
        // Flush texture cache
        CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
        
    }

    void ARCameraView::draw(int x,int y,float width,float height){
        
        // provides a way to pass through into FBO drawing so you don't have to remember two different
        // functions.
        if(mUseFbo){
            drawScaled(x,y,width,height);
        }else{
        
            // if we're not using the fbo, then just draw with the vbo.
            cameraConvertShader.begin();
            vMesh.draw(GL_TRIANGLE_STRIP, 0, 16);
            cameraConvertShader.end();
        }
        
        
        
    }
    
    void ARCameraView::drawScaled(int x,int y,float width,float height){
        
        // if parameter values are 0 - use the values that might have been
        // set with one of the other setter functions.
        
        if(x == 0){
            x = xShift;
        }
        
        if(y == 0){
            y = yShift;
        }
        
        if(width == 0){
            width = cameraScaledSize.getWidth();
        }
        
        if(height == 0){
            height = cameraScaledSize.getHeight();
        }
        
        
        // Adjust drawing as necessary .
        switch(UIDevice.currentDevice.orientation){
            case UIDeviceOrientationFaceUp:
                
                if(deviceOrientation == UIDeviceOrientationLandscapeLeft ||
                   deviceOrientation == UIDeviceOrientationLandscapeRight){
                    cameraFbo.draw(xShift,yShift,cameraScaledSize.getWidth(),cameraScaledSize.getHeight());
                }else{
                    cameraFbo.draw(xShift,yShift,cameraScaledSize.getHeight(),cameraScaledSize.getWidth());
                }
                break;
                
            case UIDeviceOrientationFaceDown:
                break;
                
            case UIDeviceOrientationUnknown:
              cameraFbo.draw(xShift,yShift,cameraScaledSize.getHeight(),cameraScaledSize.getWidth());
                
                break;
            case UIDeviceOrientationPortraitUpsideDown:
           cameraFbo.draw(xShift,yShift,cameraScaledSize.getHeight(),cameraScaledSize.getWidth());
                break;
                
            case UIDeviceOrientationPortrait:
              cameraFbo.draw(xShift,yShift,cameraScaledSize.getHeight(),cameraScaledSize.getWidth());
                break;
                
            case UIDeviceOrientationLandscapeLeft:
           cameraFbo.draw(xShift,yShift,cameraScaledSize.getWidth(),cameraScaledSize.getHeight());
                
                break;
                
            case UIDeviceOrientationLandscapeRight:
             cameraFbo.draw(xShift,yShift,cameraScaledSize.getWidth(),cameraScaledSize.getHeight());
                break;
        }
        
    }

      void ARCameraView::updateInterfaceOrientation(){
        
        switch(UIDevice.currentDevice.orientation){
            case UIDeviceOrientationFaceUp:
                orientation = UIInterfaceOrientationPortrait;
                break;
                
            case UIDeviceOrientationFaceDown:
                orientation = UIInterfaceOrientationPortrait;
                break;
                
            case UIInterfaceOrientationUnknown:
                orientation = UIInterfaceOrientationPortrait;
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                orientation = UIInterfaceOrientationPortrait;
                break;
                
            case UIDeviceOrientationPortrait:
                orientation = UIInterfaceOrientationPortrait;
                
                break;
                
                // for the next two cases - I know it's opposite land - but trust me it works :p
                
            case UIDeviceOrientationLandscapeLeft:
                orientation = UIInterfaceOrientationLandscapeRight;
                break;
                
                
            case UIDeviceOrientationLandscapeRight:
                orientation = UIInterfaceOrientationLandscapeLeft;
                break;
        }
        
    }

    //! Sets the x and y position of where the camera image is placed.
    void ARCameraView::setCameraImagePosition(int xShift, int yShift){
        this->xShift = xShift;
        this->yShift = yShift;
    }
    
    ARObjects::ARCameraMatrices ARCameraView::getMatricesForOrientation(UIInterfaceOrientation orientation,float near, float far){
        cameraMatrices.cameraView = ARUtils::toMat4([session.currentFrame.camera viewMatrixForOrientation:orientation]);
        
        cameraMatrices.cameraProjection = ARUtils::toMat4([session.currentFrame.camera projectionMatrixForOrientation:orientation viewportSize:mResolution zNear:(CGFloat)near zFar:(CGFloat)far]);
        
        return cameraMatrices;
    }
    

    // ============== PRIVATE ================= //
    void ARCameraView::calculateCameraImageFraming(){
        
        // try to fit the camera capture width within the device's viewport.
        // default capture dimensions seem to be 1280x720 regardless of device and orientation.
        cameraScaledSize = ofRectangle(0,0,mCameraFrameDimensions.x,mCameraFrameDimensions.y);
        
        ofRectangle screen;
        
        // this appears to fix inconsistancies in the image that occur in the difference in
        // startup orientation.
        if(UIDevice.currentDevice.orientation == UIDeviceOrientationPortrait){
            screen = ofRectangle(0,0,ofGetWindowWidth(),ofGetWindowHeight());
        }else{
            screen = ofRectangle(0,0,ofGetWindowHeight(),ofGetWindowWidth());
        }
        
        cameraScaledSize.scaleTo(screen,OF_ASPECT_RATIO_KEEP);
        
        // scale up rectangle based on aspect ratio of scaled capture dimensions.
        auto scaleVal = [[UIScreen mainScreen] scale];
        
        cameraScaledSize.scaleFromCenter(scaleVal);
    }
    
    
    void ARCameraView::updateFBO(){
        if(mUseFbo){
            // write image to fbo
            cameraFbo.begin();
            cameraConvertShader.begin();
            
            switch(UIDevice.currentDevice.orientation){
                case UIDeviceOrientationFaceUp:
                    cameraConvertShader.setUniform1i("isPortraitOrientation", true);
                    break;
                case UIDeviceOrientationFaceDown:
                    break;
                    
                case UIDeviceOrientationUnknown:
                    cameraConvertShader.setUniform1i("isPortraitOrientation", true);
                    break;
                case UIDeviceOrientationPortraitUpsideDown:
                    
                    cameraConvertShader.setUniform1i("isPortraitOrientation", true);
                    break;
                    
                case UIDeviceOrientationPortrait:
                    
                    cameraConvertShader.setUniform1i("isPortraitOrientation", true);
                    
                    break;
                    
                case UIDeviceOrientationLandscapeLeft:
                    
                    cameraConvertShader.setUniform1i("isPortraitOrientation", false);
                    break;
                    
                case UIDeviceOrientationLandscapeRight:
                    
                    cameraConvertShader.setUniform1i("isPortraitOrientation", false);
                    break;
            }
            
            vMesh.draw(GL_TRIANGLE_STRIP, 0, 16);
            cameraConvertShader.end();
            cameraFbo.end();
        }
    }
    
    void ARCameraView::buildFBO(int width,int height){
            
        // allocate FBO - note defaults are 4000x4000 which may impact overall memory perf
        cameraFbo.allocate(width,height, GL_RGBA);
        cameraFbo.getTexture().getTextureData().bFlipTexture = true;
    }


     void ARCameraView::buildCameraFrame(CVPixelBufferRef pixelBuffer){
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        
        
        // ========= RELEASE DATA PREVIOUSLY HELD ================= //
        
        CVBufferRelease(yTexture);
        CVBufferRelease(CbCrTexture);
        
        
        // ========= ROTATE IMAGES ================= //
        
        cameraConvertShader.begin();
        //cameraConvertShader.setUniformMatrix4f("rotationMatrix", rotation);
        
        cameraConvertShader.end();
        
        // ========= BUILD CAMERA TEXTURES ================= //
        yTexture = createTextureFromPixelBuffer(pixelBuffer, 0);
        
        int width = (int) CVPixelBufferGetWidth(pixelBuffer);
        int height = (int) CVPixelBufferGetHeight(pixelBuffer);
        
        CbCrTexture = createTextureFromPixelBuffer(pixelBuffer, 1,GL_LUMINANCE_ALPHA,width / 2, height / 2);
        
        
        // correct texture wrap and filtering of Y texture
        glBindTexture(CVOpenGLESTextureGetTarget(yTexture), CVOpenGLESTextureGetName(yTexture));
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,GL_LINEAR);
        glBindTexture(CVOpenGLESTextureGetTarget(yTexture), 0);
        
        
        // correct texture wrap and filtering of CbCr texture
        glBindTexture(CVOpenGLESTextureGetTarget(CbCrTexture), CVOpenGLESTextureGetName(CbCrTexture));
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,GL_LINEAR);
        
        glBindTexture(CVOpenGLESTextureGetTarget(CbCrTexture), 1);
        
        
        // write uniforms values to shader
        cameraConvertShader.begin();
        
        
         cameraConvertShader.setUniform2f("resolution",mResolution.width,mResolution.height);
        cameraConvertShader.setUniformTexture("yMap", CVOpenGLESTextureGetTarget(yTexture), CVOpenGLESTextureGetName(yTexture), 0);
        
        cameraConvertShader.setUniformTexture("uvMap", CVOpenGLESTextureGetTarget(CbCrTexture), CVOpenGLESTextureGetName(CbCrTexture), 1);
        
        cameraConvertShader.end();
        
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        
        
    }
    
    CVOpenGLESTextureRef ARCameraView::createTextureFromPixelBuffer(CVPixelBufferRef pixelBuffer,int planeIndex,GLenum format,int width,int height){
        CVOpenGLESTextureRef texture = NULL;
        
        if(width == 0 || height == 0){
            width = (int) CVPixelBufferGetWidth(pixelBuffer);
            height = (int) CVPixelBufferGetHeight(pixelBuffer);
        }
        
        CVReturn err = noErr;
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           format,
                                                           width,
                                                           height,
                                                           format,
                                                           GL_UNSIGNED_BYTE,
                                                           planeIndex,
                                                           &texture);
        
        if (err != kCVReturnSuccess) {
            CVBufferRelease(texture);
            texture = nil;
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        return texture;
    }

    void ARCameraView::buildScalingRects(){
           // try to fit the camera capture width within the device's viewport.
        // default capture dimensions seem to be 1280x720 regardless of device and orientation.
        ofRectangle cam,screen;
        
        cam = ofRectangle(0,0,mCameraFrameDimensions.x,mCameraFrameDimensions.y);
        
        // this appears to fix inconsistancies in the image that occur in the difference in
        // startup orientation.
        if(UIDevice.currentDevice.orientation == UIDeviceOrientationPortrait){
            screen = ofRectangle(0,0,ofGetWindowWidth(),ofGetWindowHeight());
        }else{
            screen = ofRectangle(0,0,ofGetWindowHeight(),ofGetWindowWidth());
        }
        
        cam.scaleTo(screen,OF_ASPECT_RATIO_KEEP);
        
        // scale up rectangle based on aspect ratio of scaled capture dimensions.
        auto scaleVal = [[UIScreen mainScreen] scale];

        cam.scaleFromCenter(scaleVal);
        
        mViewportDimensions.x = cam.getWidth();
        mViewportDimensions.y = cam.getHeight();
    }
    
    void ARCameraView::updatePlaneTexCoords(){
        // see
        // https://developer.apple.com/documentation/arkit/arframe/2923543-displaytransformfororientation?language=objc
        // this is more or less from the default project example.
      
        CGAffineTransform displayToCameraTransform = CGAffineTransformInvert([session.currentFrame displayTransformForOrientation:orientation viewportSize:mResolution]);
        
        for (NSInteger index = 0; index < 4; index++) {
            NSInteger textureCoordIndex = 4 * index + 2;
            CGPoint textureCoord = CGPointMake(kImagePlaneVertexData[textureCoordIndex], kImagePlaneVertexData[textureCoordIndex + 1]);
            CGPoint transformedCoord = CGPointApplyAffineTransform(textureCoord, displayToCameraTransform);
            kImagePlaneVertexData[textureCoordIndex] = transformedCoord.x;
            kImagePlaneVertexData[textureCoordIndex + 1] = transformedCoord.y;
            vMesh.updateVertexData(kImagePlaneVertexData, 16);
        }
    }
}

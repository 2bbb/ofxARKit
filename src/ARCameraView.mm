

#include "ARCameraView.h"

namespace ARCore {

    ARCameraView::ARCameraView(ARSession * session, bool mUseFbo):
    mUseFbo(mUseFbo){

        //! Store session.
        this->session = session;

        //! Get the resolution we're capturing at.
        auto dimensions = session.currentFrame.camera.imageResolution;


        // set camera frame dimensions.
        mCameraFrameDimensions.x = diemensions.width;
        mCameraFrameDimensions.y = dimensions.height;


        // setup other variables with defaults.
        ambientIntensity = 0.0;
        orientation = [[UIApplication sharedApplication] statusBarOrientation];
        yTexture = NULL;
        CbCrTexture = NULL;
        near = 0.1;
        far = 1000.0;
        debugMode = false;
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

    void ARCameraView::setCameraNearFar(float near, float far){
      // check to see if values were passed in, if not, do nothing.

      if(near != 0.0){
        this->near = near;
      }

      if(far != 0.0){
        this->far = far;
      }
    }


    void ARCameraView::update(){
        // if we haven't set a session - just stop things here.
        if(!session){
            return;
        }

        if(debugMode){
            // update state and reason
            trackingStateReason = session.currentFrame.camera.trackingStateReason;
        }

        // update the camera
        getMatricesForOrientation(orientation,near,far);

        // grab current frame pixels from camera
        CVPixelBufferRef pixelBuffer = session.currentFrame.capturedImage;
            
         if (CVPixelBufferGetPlaneCount(pixelBuffer) >= 2) {
            buildCameraFrame(pixelBuffer);
            
            
            
            // Periodic texture cache flush every frame
            CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
        }
        

    }

    void ARCameraView::rotateCameraFrame(float angle){
        cameraRotation.makeIdentityMatrix();
        cameraRotation.makeRotationMatrix(angle, ofVec3f(0,0,1));
    }
    void ARCameraView::draw(){

    }
    void ARCameraView::setInterfaceOrientation(UIInterfaceOrientation orientation){
      this->orientation = orientation;
    }

    //! Sets the x and y position of where the camera image is placed.
    void ARCameraView::setCameraImagePosition(float xShift,float yShift){
        this->xShift = xShift;
        this->yShift = yShift;
    }

    ARCameraMatrices ARCameraView::getMatricesForOrientation(UIInterfaceOrientation orientation,float near, float far){
    
        cameraMatrices.cameraView = toMat4([session.currentFrame.camera viewMatrixForOrientation:orientation]);
        cameraMatrices.cameraProjection = toMat4([session.currentFrame.camera projectionMatrixForOrientation:orientation viewportSize:viewportSize zNear:(CGFloat)near zFar:(CGFloat)far]);
        
        return cameraMatrices;
    }
    


    // ============== PRIVATE ================= //
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
        cameraConvertShader.setUniformMatrix4f("rotationMatrix", rotation);

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

        glBindTexture(CVOpenGLESTextureGetTarget(CbCrTexture), 0);


        // write uniforms values to shader
        cameraConvertShader.begin();


        cameraConvertShader.setUniform2f("resolution", viewportSize.width,viewportSize.height);
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

        mViewportDimensionss.x = cam.getWidth();
        mViewportDimensionss.y = cam.getHeight();
    }

    void ARCamera::logTrackingState(){

        if(debugMode){
            switch(trackingStateReason){
                case ARTrackingStateReasonNone:
                    ofLog(OF_LOG_NOTICE,"Tracking state is a-ok!");
                    break;

                case ARTrackingStateReasonInitializing:
                    ofLog(OF_LOG_NOTICE,"Tracking is warming up and waiting for enough information to start tracking");
                    break;

                case ARTrackingStateReasonExcessiveMotion:
                    ofLog(OF_LOG_ERROR,"There is excessive motion at the moment, tracking is affected.");
                    break;

                case ARTrackingStateReasonInsufficientFeatures:
                    ofLog(OF_LOG_ERROR,"There are not enough features found to enable tracking");
                    break;
            }
        }
    }
}



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


    void ARCameraView::update(){
        // if we haven't set a session - just stop things here.
        if(!session){
            return;
        }
        
    }

    void ARCameraView::draw(){
        
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
    void ARCameraView::setCameraImagePosition(float xShift,float yShift){
        this->xShift = xShift;
        this->yShift = yShift;
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
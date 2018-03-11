
#pragma once

#include <stdio.h>
#include <ARKit/ARKit.h>
#include "ARUtils.h"
#include "ARShaders.h"
#include "ARDebugUtils.h"
#include "ofxiOS.h"
#include "ARUtils.h"
#include "ARObjects.h"

namespace ARCore {

    typedef std::shared_ptr<class ARCameraView>ARCameraViewRef;
    
    // prepare for glm move with newer version of oF
    typedef ofVec2f vec2;
    typedef ofVec3f vec3;
    typedef ofMatrix4x4 mat4;


    class ARCameraView {

        //! Session object that's being used for ARKit
        ARSession * session;

        //! The current frame dimensions. This will change depending on 
        //! the settings implemented in your Session's initialization and 
        //! your device's capabilities. 
        vec2 mCameraFrameDimensions;

        //! The calculated viewport dimensions for a device. Primarily necessary for iPads
        vec2 mViewportDimensions;
        
        //! Normal resolution of the device as defined by ofGetWindowWidth / ofGetWindowHeight()
        CGSize mResolution;
        
        //! A flag for triggering debug related items.
        bool mDebugMode;

        //! A flag to set for whether or not you want the view to return an FBO.  
        bool mUseFbo;

        //! the current ambient light intensity
        float ambientIntensity;
        
        //! the current ambient color temperature
        float ambientColorTemperature;

        //! Rotation matrix for tweaking the camera to the correct orientaiton.
        mat4 cameraRotation;
        
        // ============== IMAGE SCALING RELATED =================== //
        
        //! Contains the calculated image scaling for the device.
        ofRectangle cameraScaledSize;
        
        //! Fbo for rendering scaled versions of the camera image and/or for doing
        //! things with the camera feed.
        ofFbo cameraFbo;
        

        // ============= VIDEO / CAMERA / TRACKING RELATED ================ //
        CVOpenGLESTextureRef yTexture;
        CVOpenGLESTextureRef CbCrTexture;
        CVOpenGLESTextureCacheRef _videoTextureCache;
        
        //! The near clip value to use when obtaining projection/view matrices
        float near;
        
        //! The far clip value to use when obtaining projection/view matrices
        float far;
        
        //! The current tracking state of the camera
        ARTrackingState trackingState;
        
        //! The reason for when a tracking state might be limited.
        ARTrackingStateReason trackingStateReason;

         //! current orientation to use to get proper projection and view matrices
        UIInterfaceOrientation orientation;
        
        //! The current device's actual orientation;
        UIDeviceOrientation deviceOrientation;

        //! The offset for how the image should be positioned when using an FBO to 
        //! render the camera image.
        float xShift,yShift;
        
        //! the dimensions of the calculated camera image. 
        ofVec2f cameraDimensions;
        
        ARObjects::ARCameraMatrices cameraMatrices;

        // ============= MESH / RENDERING =============== //
        
        //! shader to color convert the camera image
        ofShader cameraConvertShader;
        
        //! mesh to render camera image
        ofVbo vMesh;
        
        //! vertex data to render the camera image
        float kImagePlaneVertexData[16] = {
            -1.0, -1.0,  0.0, 1.0,
            1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
            1.0,  1.0,  1.0, 0.0,
        };
        
        // ============== PRIVATE FUNCTIONS ============ // 
        
        //! Attempts to calculate proper values in how the camera image is rendered.
        //! Used only for iPads - iPhones appear to be mostly immune to any scaling issues. 
        void calculateCameraImageFraming();
        
        //! Builds FBO so you can use camera feed for other purposes
        //! or to scale the feed to better fit your device.
        void buildFBO(int width=4000,int height=4000);

          //! Converts the CVPixelBufferIndex into a OpenGL texture
        CVOpenGLESTextureRef createTextureFromPixelBuffer(CVPixelBufferRef pixelBuffer,int planeIndex,GLenum format=GL_LUMINANCE,int width=0,int height=0);
        
        //! Constructs camera frame from pixel data
        void buildCameraFrame(CVPixelBufferRef pixelBuffer);

        //! Figure out necessary calculations to correctly scale image
        //! primarily to iPad sized viewports.
        void buildScalingRects();
        
        //! Updates the texture coordinates of the drawing mesh depending on
        //! the current state of the device. 
        void updatePlaneTexCoords();
        
        //! Updates the internal FBO if enabled with the new camera image.
        void updateFBO();
        public:
            ARCameraView(ARSession * session,bool mUseFbo=false);

        static ARCameraViewRef create(ARSession * session, bool mUseFbo=false){
            return ARCameraViewRef(new ARCameraView(session,mUseFbo));
        }
            void update();
            void draw(int x=0,int y=0,float width=0.0f,float height=0.0f);
            void drawScaled(int x=0,int y=0,float width=0.0f,float height=0.0f);
        
            //! When using an FBO, sets the x and y offset of where the image is drawn.
            void setCameraImagePosition(int xShift,int yShift);

            //! Update the device's interface orientation settings based on the current
            //! based on the current device's actual rotation. 
            void updateInterfaceOrientation();
        
            //! updates the current projection and view matricies currently seen by ARKit.
            ARObjects::ARCameraMatrices getMatricesForOrientation(UIInterfaceOrientation orientation,float near, float far);
    };
}

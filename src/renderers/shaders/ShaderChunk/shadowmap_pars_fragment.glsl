#ifdef USE_SHADOWMAP

	#if NUM_DIR_LIGHTS > 0

		uniform sampler2D directionalShadowMap[ NUM_DIR_LIGHTS ];
		varying vec4 vDirectionalShadowCoord[ NUM_DIR_LIGHTS ];

	#endif

	#if NUM_SPOT_LIGHTS > 0

		uniform sampler2D spotShadowMap[ NUM_SPOT_LIGHTS ];
		varying vec4 vSpotShadowCoord[ NUM_SPOT_LIGHTS ];

	#endif

	#if NUM_POINT_LIGHTS > 0

		uniform sampler2D pointShadowMap[ NUM_POINT_LIGHTS ];
		varying vec4 vPointShadowCoord[ NUM_POINT_LIGHTS ];

	#endif
	/* PCSS implementation inspired from http://developer.download.nvidia.com/whitepapers/2008/PCSS_Integration.pdf
	   Spot light and directional lights are treated differently. For directional light, there is no clear Physical
     meaning of shadow radius. Instead, a more intuitive parameter "spreadAngle" is used for directional lights,
		 to calculate the searchRadius to find blocker depth, and to find the filter radius for PCF.
	*/

	#if defined( SHADOWMAP_TYPE_PCSS )
		#define PCSS_QUALITY_LEVEL 5
		#define PCSS_NUM_POISSON_SAMPLES 16
		#define PCSS_ROTATE_POISSON_SAMPLES 1

		vec2 poissonDisk[PCSS_NUM_POISSON_SAMPLES];

		void initPercentCloserSoftShadow( const in vec2 randomSeed )	{

			poissonDisk[0] = vec2(-0.94201624, -0.39906216 );
			poissonDisk[1] = vec2( 0.94558609, -0.76890725 );
			poissonDisk[2] = vec2( -0.094184101, -0.92938870 );
			poissonDisk[3] = vec2( 0.34495938, 0.29387760 );
			poissonDisk[4] = vec2( -0.91588581, 0.45771432 );
			poissonDisk[5] = vec2( -0.81544232, -0.87912464 );
			poissonDisk[6] = vec2( -0.38277543, 0.27676845 );
			poissonDisk[7] = vec2( 0.97484398, 0.75648379 );
			poissonDisk[8] = vec2( 0.44323325, -0.97511554 );
			poissonDisk[9] = vec2( 0.53742981, -0.47373420 );
			poissonDisk[10] = vec2( -0.26496911, -0.41893023 );
			poissonDisk[11] = vec2( 0.79197514, 0.19090188 );
			poissonDisk[12] = vec2( -0.24188840, 0.99706507 );
			poissonDisk[13] = vec2( -0.81409955, 0.91437590 );
			poissonDisk[14] = vec2( 0.19984126, 0.78641367 );
			poissonDisk[15] = vec2( 0.14383161, -0.14100790 );
		}

		mat2 createRotationMatrix( const in vec2 randomSeed ) {
			float angle = rand( randomSeed ) * PI2;
			float c = cos( angle ), s = sin( angle );
			return mat2( c, s, -s, c );
		}

		float penumbraSize( const in float zReceiverLightSpace, const in float zBlockerLightSpace ) { // Parallel plane estimation
			return (zReceiverLightSpace - zBlockerLightSpace) / zBlockerLightSpace;
		}

		float findBlockerLightZ( sampler2D shadowMap, const in vec2 uv, const in float zReceiverClipSpace, const in float zReceiverLightSpace, const in float shadowRadius, const in float spreadAngle, const in vec3 shadowCameraParams, const in vec2 randomSeed, const int lightType ) {
			// This uses similar triangles to compute what
			// area of the shadow map we should search
			float lightFrustrumWidth = 2.0 * shadowCameraParams.y * tan(shadowCameraParams.x * 0.5);
			float searchRadius = 0.0;
			searchRadius = ( lightType == 0) ? zReceiverLightSpace * spreadAngle/shadowCameraParams.x : ( shadowRadius / lightFrustrumWidth ) * ( zReceiverLightSpace - shadowCameraParams.y ) / zReceiverLightSpace;
			float blockerLightZSum = 0.0;
			int numBlockers = 0;

			float angle = rand( randomSeed ) * PI2;
			float s = sin(angle);
			float c = cos(angle);
			for( int i = 0; i < PCSS_NUM_POISSON_SAMPLES; i++ ) {
			#if PCSS_ROTATE_POISSON_SAMPLES == 1
				vec2 poissonSample = vec2(poissonDisk[i].y * c + poissonDisk[i].x * s, poissonDisk[i].y * -s + poissonDisk[i].x * c);
			#else
				vec2 poissonSample = poissonDisk[i];
			#endif
				float shadowMapDepth = unpackRGBAToDepth( texture2D( shadowMap, uv + poissonSample * searchRadius ) );
				if ( shadowMapDepth < zReceiverClipSpace ) {
					blockerLightZSum += shadowMapDepth;
					numBlockers ++;
				}

			}

			if( numBlockers == 0 ) return -1.0;

			return blockerLightZSum / float( numBlockers );
		}

		float percentCloserFilter( sampler2D shadowMap, vec2 uv, float receiverClipZ, float filterRadius, const in vec2 randomSeed ) {
			int numBlockers = 0;
			float angle = rand( randomSeed ) * PI2;
			float s = sin(angle);
			float c = cos(angle);

			for( int i = 0; i < PCSS_NUM_POISSON_SAMPLES; i ++ ) {
			#if PCSS_ROTATE_POISSON_SAMPLES == 1
				vec2 poissonSample = vec2(poissonDisk[i].y * c + poissonDisk[i].x * s, poissonDisk[i].y * -s + poissonDisk[i].x * c);
			#else
				vec2 poissonSample = poissonDisk[i];
			#endif
				vec2 uvOffset = poissonSample * filterRadius;

				float blockerClipZ = unpackRGBAToDepth( texture2D( shadowMap, uv + uvOffset ) );
				if( receiverClipZ <= blockerClipZ ) numBlockers ++;

				blockerClipZ = unpackRGBAToDepth( texture2D( shadowMap, uv - uvOffset ) );
				if( receiverClipZ <= blockerClipZ ) numBlockers ++;

			}

			return float( numBlockers ) / ( 2.0 * float( PCSS_NUM_POISSON_SAMPLES ) );
		}

		float percentCloserSoftShadow( sampler2D shadowMap, const in float shadowRadius, const in float spreadAngle, const in vec3 shadowCameraParams, const in vec4 coords, const int lightType ) {

			vec2 uv = coords.xy;
			float receiverLightZ = coords.z;
			float cameraNear = shadowCameraParams.y, cameraFar = shadowCameraParams.z;
			float zReceiverLightSpace;
			if(lightType == 0)
				zReceiverLightSpace = -orthographicDepthToViewZ( receiverLightZ, cameraNear, cameraFar );
			else
				zReceiverLightSpace = -perspectiveDepthToViewZ( receiverLightZ, cameraNear, cameraFar );

			// STEP 1: blocker search
			float blockerLightZ = findBlockerLightZ( shadowMap, uv, receiverLightZ, zReceiverLightSpace, shadowRadius, spreadAngle, shadowCameraParams, uv, lightType );

			//There are no occluders so early out (this saves filtering)
			if( blockerLightZ == -1.0 ) return 1.0;

			float avgBlockerDepthLightSpace;
			float filterRadius = 0.0;

			// STEP 2: penumbra size
			if(lightType == 0) {
				avgBlockerDepthLightSpace = -orthographicDepthToViewZ( blockerLightZ, cameraNear, cameraFar );
				filterRadius = (zReceiverLightSpace - avgBlockerDepthLightSpace) * spreadAngle/shadowCameraParams.x;
			}
			else {
				avgBlockerDepthLightSpace = -perspectiveDepthToViewZ( blockerLightZ, cameraNear, cameraFar );
				float penumbraRatio = penumbraSize( zReceiverLightSpace, avgBlockerDepthLightSpace );
				float lightFrustrumWidth = 2.0 * cameraNear * tan(shadowCameraParams.x * 0.5);
				filterRadius = penumbraRatio * ( shadowRadius/lightFrustrumWidth ) * cameraNear / zReceiverLightSpace;
			}
			// STEP 3: filtering
			return percentCloserFilter( shadowMap, uv, receiverLightZ, filterRadius, uv );
		}

	#endif

    #if NUM_RECT_AREA_LIGHTS > 0
        // TODO (abelnation): create uniforms for area light shadows
    #endif

	float texture2DCompare( sampler2D depths, vec2 uv, float compare ) {

		return step( compare, unpackRGBAToDepth( texture2D( depths, uv ) ) );

	}

	float texture2DShadowLerp( sampler2D depths, vec2 size, vec2 uv, float compare ) {

		const vec2 offset = vec2( 0.0, 1.0 );

		vec2 texelSize = vec2( 1.0 ) / size;
		vec2 centroidUV = floor( uv * size + 0.5 ) / size;

		float lb = texture2DCompare( depths, centroidUV + texelSize * offset.xx, compare );
		float lt = texture2DCompare( depths, centroidUV + texelSize * offset.xy, compare );
		float rb = texture2DCompare( depths, centroidUV + texelSize * offset.yx, compare );
		float rt = texture2DCompare( depths, centroidUV + texelSize * offset.yy, compare );

		vec2 f = fract( uv * size + 0.5 );

		float a = mix( lb, lt, f.y );
		float b = mix( rb, rt, f.y );
		float c = mix( a, b, f.x );

		return c;

	}

	void initShadows() {

		#if defined( SHADOWMAP_TYPE_PCSS )

		  initPercentCloserSoftShadow( vViewPosition.xy );

		#endif

	}

	float getShadow( sampler2D shadowMap, vec2 shadowMapSize, float shadowBias, float shadowRadius, float spreadAngle, vec3 shadowCameraParams, vec4 shadowCoord, const int lightType ) {

		shadowCoord.xyz /= shadowCoord.w;
		shadowCoord.z += shadowBias;

		// if ( something && something ) breaks ATI OpenGL shader compiler
		// if ( all( something, something ) ) using this instead

		bvec4 inFrustumVec = bvec4 ( shadowCoord.x >= 0.0, shadowCoord.x <= 1.0, shadowCoord.y >= 0.0, shadowCoord.y <= 1.0 );
		bool inFrustum = all( inFrustumVec );

		bvec2 frustumTestVec = bvec2( inFrustum, shadowCoord.z <= 1.0 );

		bool frustumTest = all( frustumTestVec );

		if ( frustumTest ) {

		#if defined( SHADOWMAP_TYPE_PCF )

			vec2 texelSize = vec2( 1.0 ) / shadowMapSize;

			float dx0 = - texelSize.x * shadowRadius;
			float dy0 = - texelSize.y * shadowRadius;
			float dx1 = + texelSize.x * shadowRadius;
			float dy1 = + texelSize.y * shadowRadius;

			return (
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy, shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, dy1 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy1 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, dy1 ), shadowCoord.z )
			) * ( 1.0 / 9.0 );

		#elif defined( SHADOWMAP_TYPE_PCF_SOFT )

			vec2 texelSize = vec2( 1.0 ) / shadowMapSize;

			float dx0 = - texelSize.x * shadowRadius;
			float dy0 = - texelSize.y * shadowRadius;
			float dx1 = + texelSize.x * shadowRadius;
			float dy1 = + texelSize.y * shadowRadius;

			return (
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( dx0, dy0 ), shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( 0.0, dy0 ), shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( dx1, dy0 ), shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( dx0, 0.0 ), shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy, shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( dx1, 0.0 ), shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( dx0, dy1 ), shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( 0.0, dy1 ), shadowCoord.z ) +
				texture2DShadowLerp( shadowMap, shadowMapSize, shadowCoord.xy + vec2( dx1, dy1 ), shadowCoord.z )
			) * ( 1.0 / 9.0 );

		#elif defined( SHADOWMAP_TYPE_PCSS )

		  return percentCloserSoftShadow( shadowMap, shadowRadius, spreadAngle, shadowCameraParams, shadowCoord, lightType );

		#else // no percentage-closer filtering:

			return texture2DCompare( shadowMap, shadowCoord.xy, shadowCoord.z );

		#endif

		}

		return 1.0;

	}

	// cubeToUV() maps a 3D direction vector suitable for cube texture mapping to a 2D
	// vector suitable for 2D texture mapping. This code uses the following layout for the
	// 2D texture:
	//
	// xzXZ
	//  y Y
	//
	// Y - Positive y direction
	// y - Negative y direction
	// X - Positive x direction
	// x - Negative x direction
	// Z - Positive z direction
	// z - Negative z direction
	//
	// Source and test bed:
	// https://gist.github.com/tschw/da10c43c467ce8afd0c4

	vec2 cubeToUV( vec3 v, float texelSizeY ) {

		// Number of texels to avoid at the edge of each square

		vec3 absV = abs( v );

		// Intersect unit cube

		float scaleToCube = 1.0 / max( absV.x, max( absV.y, absV.z ) );
		absV *= scaleToCube;

		// Apply scale to avoid seams

		// two texels less per square (one texel will do for NEAREST)
		v *= scaleToCube * ( 1.0 - 2.0 * texelSizeY );

		// Unwrap

		// space: -1 ... 1 range for each square
		//
		// #X##		dim    := ( 4 , 2 )
		//  # #		center := ( 1 , 1 )

		vec2 planar = v.xy;

		float almostATexel = 1.5 * texelSizeY;
		float almostOne = 1.0 - almostATexel;

		if ( absV.z >= almostOne ) {

			if ( v.z > 0.0 )
				planar.x = 4.0 - v.x;

		} else if ( absV.x >= almostOne ) {

			float signX = sign( v.x );
			planar.x = v.z * signX + 2.0 * signX;

		} else if ( absV.y >= almostOne ) {

			float signY = sign( v.y );
			planar.x = v.x + 2.0 * signY + 2.0;
			planar.y = v.z * signY - 2.0;

		}

		// Transform to UV space

		// scale := 0.5 / dim
		// translate := ( center + 0.5 ) / dim
		return vec2( 0.125, 0.25 ) * planar + vec2( 0.375, 0.75 );

	}

	float getPointShadow( sampler2D shadowMap, vec2 shadowMapSize, float shadowBias, float shadowRadius, vec4 shadowCoord ) {

		vec2 texelSize = vec2( 1.0 ) / ( shadowMapSize * vec2( 4.0, 2.0 ) );

		// for point lights, the uniform @vShadowCoord is re-purposed to hold
		// the distance from the light to the world-space position of the fragment.
		vec3 lightToPosition = shadowCoord.xyz;

		// bd3D = base direction 3D
		vec3 bd3D = normalize( lightToPosition );
		// dp = distance from light to fragment position
		float dp = ( length( lightToPosition ) - shadowBias ) / 1000.0;

		#if defined( SHADOWMAP_TYPE_PCF ) || defined( SHADOWMAP_TYPE_PCF_SOFT )

			vec2 offset = vec2( - 1, 1 ) * shadowRadius * texelSize.y;

			return (
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xyy, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yyy, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xyx, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yyx, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xxy, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yxy, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xxx, texelSize.y ), dp ) +
				texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yxx, texelSize.y ), dp )
			) * ( 1.0 / 9.0 );

		#else // no percentage-closer filtering

			return texture2DCompare( shadowMap, cubeToUV( bd3D, texelSize.y ), dp );

		#endif

	}

#endif

/******************************************************************************
 * The MIT License (MIT)
 * 
 * Copyright (c) 2014 Crytek
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/



v2f RENDERDOC_DebugVS(a2v IN)
{
	v2f OUT = (v2f)0;
	OUT.pos = float4(Position.xy + (float2(IN.pos.z,0) + IN.pos.xy*TextureResolution.xy)*Scale*ScreenAspect.xy, 0, 1)-float4(1.0,-1.0,0,0);
	OUT.tex.xy = float2(IN.pos.x, -IN.pos.y);
	return OUT;
}

// main texture display shader, used for the texture viewer. It samples the right resource
// for the type and applies things like the range check and channel masking.
// It also does a couple of overlays that we can get 'free' like NaN/inf checks
// or range clipping
float4 RENDERDOC_TexDisplayPS(v2f IN) : SV_Target0
{
	bool uintTex = OutputDisplayFormat & TEXDISPLAY_UINT_TEX;
	bool sintTex = OutputDisplayFormat & TEXDISPLAY_SINT_TEX;

	float4 col = 0;
	uint4 ucol = 0;
	int4 scol = 0;

	if(uintTex)
	{
		ucol = SampleTextureUInt4(OutputDisplayFormat & TEXDISPLAY_TYPEMASK,
								  IN.tex.xy, Slice, MipLevel, TextureResolutionPS);
	}
	else if(sintTex)
	{
		scol = SampleTextureInt4 (OutputDisplayFormat & TEXDISPLAY_TYPEMASK,
								  IN.tex.xy, Slice, MipLevel, TextureResolutionPS);
	}
	else
	{
		col = SampleTextureFloat4(OutputDisplayFormat & TEXDISPLAY_TYPEMASK, (ScalePS < 1 && MipLevel == 0),
								  IN.tex.xy, Slice, MipLevel, TextureResolutionPS);
	}
	
	if(RawOutput)
	{
		if(uintTex)
			return asfloat(ucol);
		else if(sintTex)
			return asfloat(scol);
		else
			return col;
	}

    // RGBM encoding
	if(WireframeColour.x > 0.0f)
	{
		if(uintTex)
			ucol = float4(ucol.rgb * ucol.a * (uint)(WireframeColour.x), 1.0f);
		else if(sintTex)
			scol = float4(scol.rgb * scol.a * (int)(WireframeColour.x), 1.0f);
		else
			col = float4(col.rgb * col.a * WireframeColour.x, 1.0f);
	}

	if(uintTex)
		col = (float4)(ucol);
	else if(sintTex)
		col = (float4)(scol);

	col = ((col - RangeMinimum)*InverseRangeSize);

	col = lerp(float4(0,0,0,1), col, Channels);

	// show nans, infs and negatives
	if(OutputDisplayFormat & TEXDISPLAY_NANS)
	{
		if(isnan(col.r) || isnan(col.g) || isnan(col.b) || isnan(col.a))
		   return float4(1, 0, 0, 1);
		   
		if(isinf(col.r) || isinf(col.g) || isinf(col.b) || isinf(col.a))
		   return float4(0, 1, 0, 1);

		if(col.r < 0 || col.g < 0 || col.b < 0 || col.a < 0)
		   return float4(0, 0, 1, 1);
		
		col = float4(dot(col.xyz, float3(0.2126, 0.7152, 0.0722)).xxx, 1);
	}
	else if(OutputDisplayFormat & TEXDISPLAY_CLIPPING)
	{
		if(col.r < 0 || col.g < 0 || col.b < 0 || col.a < 0)
		   return float4(1, 0, 0, 1);

		if(col.r > 1 || col.g > 1 || col.b > 1 || col.a > 1)
		   return float4(0, 1, 0, 1);
		
		col = float4(dot(col.xyz, float3(0.2126, 0.7152, 0.0722)).xxx, 1);
	}
	else
	{
		// if only one channel is selected
		if(dot(Channels, 1) == 1)
		{
			// if it's alpha, just move it into rgb
			// otherwise, select the channel that's on and replicate it across all channels
			if(Channels.a == 1)
				col = float4(col.aaa, 1);
			else
				col = float4(dot(col.rgb, 1).xxx, 1);
		}
	}

	if(OutputDisplayFormat & TEXDISPLAY_GAMMA_CURVE)
	{
		col.rgb = pow(saturate(col.rgb), 2.2f);
	}
	
	return col;
}

struct MultipleOutput
{
	float4 col0 : SV_Target0;
	float4 col1 : SV_Target1;
	float4 col2 : SV_Target2;
	float4 col3 : SV_Target3;
	float4 col4 : SV_Target4;
	float4 col5 : SV_Target5;
	float4 col6 : SV_Target6;
	float4 col7 : SV_Target7;
};

struct wireframeV2F
{
	float4 pos : SV_Position;
	float3 norm : Normal;
	float3 color : COLOR;
	float2 tex : TEXCOORD0;
};

wireframeV2F RENDERDOC_WireframeHomogVS(float4 pos : POSITION, uint vid : SV_VertexID)
{
	wireframeV2F OUT = (wireframeV2F)0;
	OUT.pos = mul(pos, ModelViewProj);
	
	float2 psprite[4] =
	{
		float2(-1.0f, -1.0f),
		float2(-1.0f,  1.0f),
		float2( 1.0f, -1.0f),
		float2( 1.0f,  1.0f)
	};

	OUT.pos.xy += SpriteSize.xy*0.01f*psprite[vid%4]*OUT.pos.w;
	
	return OUT;
}

struct meshA2V
{
	float3 pos : pos;
	float2 tex : tex;
	float3 color : col;
};

wireframeV2F RENDERDOC_MeshVS(meshA2V IN, uint vid : SV_VertexID)
{
	wireframeV2F OUT = (wireframeV2F)0;

	OUT.pos = mul(float4(IN.pos, 1), ModelViewProj);
	OUT.norm = float3(0, 0, 1);
	OUT.color = IN.color;
	OUT.tex = IN.tex;
	
	return OUT;
}

[maxvertexcount(3)]
void RENDERDOC_MeshGS(triangle wireframeV2F input[3], inout TriangleStream<wireframeV2F> TriStream)
{
    wireframeV2F output;
    
    float4 faceEdgeA = mul(input[1].pos, InvProj) - mul(input[0].pos, InvProj);
    float4 faceEdgeB = mul(input[2].pos, InvProj) - mul(input[0].pos, InvProj);
    float3 faceNormal = normalize( cross(faceEdgeA.xyz, faceEdgeB.xyz) );
	
    for(int i=0; i<3; i++)
    {
        output.pos = input[i].pos;
        output.norm = faceNormal;
        output.color = input[i].color;
        output.tex = input[i].tex;
        TriStream.Append(output);
    }
    TriStream.RestartStrip();
}

float4 RENDERDOC_MeshPS(wireframeV2F IN) : SV_Target0
{
	uint type = OutputDisplayFormat;
	
	if(type == MESHDISPLAY_TEXCOORD)
		return float4(IN.tex.xy, 0, 1);
	else if(type == MESHDISPLAY_COLOR)
		return float4(IN.color.xyz, 1);
	else if(type == MESHDISPLAY_FACELIT)
	{
		float3 lightDir = normalize(float3(0, -0.3f, -1));

		return float4(WireframeColour.xyz*saturate(dot(lightDir, IN.norm)), 1);
	}
	else //if(type == MESHDISPLAY_SOLID)
		return float4(WireframeColour.xyz, 1);
}

wireframeV2F RENDERDOC_WireframeVS(float3 pos : POSITION, uint vid : SV_VertexID)
{
	wireframeV2F OUT = (wireframeV2F)0;
	OUT.pos = mul(float4(pos, 1), ModelViewProj);

	float2 psprite[4] =
	{
		float2(-1.0f, -1.0f),
		float2(-1.0f,  1.0f),
		float2( 1.0f, -1.0f),
		float2( 1.0f,  1.0f)
	};

	OUT.pos.xy += SpriteSize.xy*0.01f*psprite[vid%4]*OUT.pos.w;

	return OUT;
}

wireframeV2F RENDERDOC_FullscreenVS(uint id : SV_VertexID)
{
	wireframeV2F OUT = (wireframeV2F)0;

	float4 pos[] = {
		float4( -1.0f,  1.0f, 0.0f, 1.0f),
		float4(  3.0f,  1.0f, 0.0f, 1.0f),
		float4( -1.0f, -3.0f, 0.0f, 1.0f)
	};
	
	float2 uv[] = {
		float2(0.0f, 0.0f),
		float2(2.0f, 0.0f),
		float2(0.0f, 2.0f)
	};

	OUT.pos = pos[id];
	OUT.tex = uv[id];
	OUT.norm = float3(0, 0, 1);
	OUT.color = float3(1, 1, 1);

	return OUT;
}

MultipleOutput RENDERDOC_WireframePS(wireframeV2F IN)
{
	MultipleOutput OUT = (MultipleOutput)0;

	OUT.col0 =
	OUT.col1 =
	OUT.col2 =
	OUT.col3 =
	OUT.col4 =
	OUT.col5 =
	OUT.col6 =
	OUT.col7 =
		float4(WireframeColour.xyz, 1);

	return OUT;
}

cbuffer overlayconsts : register(b1)
{
	float4 overlaycol;
};

MultipleOutput RENDERDOC_OverlayPS(float4 IN : SV_Position)
{
	MultipleOutput OUT = (MultipleOutput)0;

	OUT.col0 =
	OUT.col1 =
	OUT.col2 =
	OUT.col3 =
	OUT.col4 =
	OUT.col5 =
	OUT.col6 =
	OUT.col7 =
		overlaycol;

	return OUT;
}

float4 RENDERDOC_CheckerboardPS(float4 IN : SV_Position) : SV_Target0
{
	float2 ab = fmod(IN.xy, 128.0.xx);

	if(
		(ab.x < 64 && ab.y < 64) ||
		(ab.x > 64 && ab.y > 64)
		)
	{
		return float4(sqrt(WireframeColour.rgb), 1);
	}

	return float4(sqrt(Channels.rgb), 1);
}
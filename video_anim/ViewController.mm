//
//  ViewController.m
//  video_anim
//
//  Created by geekgy on 16/6/29.
//  Copyright © 2016年 joycastle. All rights reserved.
//

#import "ViewController.h"
extern "C"
{
    #include "avcodec.h"
    #include "avformat.h"
    #include "swscale.h"
};

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)decode:(id)sender {
    NSString *appDirectory = [[NSBundle mainBundle] resourcePath];
    NSString *docDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    
    NSLog(@"%@", appDirectory);
    NSLog(@"%@", docDirectory);
    
    NSString *videoPath = [appDirectory stringByAppendingPathComponent:@"video.mp4"];
    
    // Initalizing these to NULL prevents segfaults!
    AVFormatContext   *pFormatCtx = NULL;
    int               i, videoStream;
    AVCodecContext    *pCodecCtxOrig = NULL;
    AVCodecContext    *pCodecCtx = NULL;
    AVCodec           *pCodec = NULL;
    AVFrame           *pFrame = NULL;
    AVFrame           *pFrameRGB = NULL;
    AVPacket          packet;
    int               frameFinished;
    int               numBytes;
    uint8_t           *buffer = NULL;
    struct SwsContext *sws_ctx = NULL;
    
    // Register all formats and codecs
    av_register_all();
    
    // Open video file
    if(avformat_open_input(&pFormatCtx, [videoPath UTF8String], NULL, NULL)!=0) {
        NSLog(@"%@", @"Couldn't open file");
        return; // Couldn't open file
    }
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx, NULL)<0) {
        NSLog(@"%@", @"Couldn't find stream information");
        return; // Couldn't find stream information
    }
    
    // Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, [videoPath UTF8String], 0);
    
    // Find the first video stream
    videoStream=-1;
    for(i=0; i<pFormatCtx->nb_streams; i++)
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO) {
            videoStream=i;
            break;
        }
    if(videoStream==-1)
        return; // Didn't find a video stream
    
    // Get a pointer to the codec context for the video stream
    pCodecCtxOrig=pFormatCtx->streams[videoStream]->codec;
    // Find the decoder for the video stream
    pCodec=avcodec_find_decoder(pCodecCtxOrig->codec_id);
    if(pCodec==NULL) {
        fprintf(stderr, "Unsupported codec!\n");
        return; // Codec not found
    }
    // Copy context
    pCodecCtx = avcodec_alloc_context3(pCodec);
    if(avcodec_copy_context(pCodecCtx, pCodecCtxOrig) != 0) {
        fprintf(stderr, "Couldn't copy codec context");
        return; // Error copying codec context
    }
    
    // Open codec
    if(avcodec_open2(pCodecCtx, pCodec, NULL)<0)
        return; // Could not open codec
    
    // Allocate video frame
    pFrame=av_frame_alloc();
    
    // Allocate an AVFrame structure
    pFrameRGB=av_frame_alloc();
    if(pFrameRGB==NULL)
        return;
    
    // Determine required buffer size and allocate buffer
    numBytes=avpicture_get_size(AV_PIX_FMT_RGB24, pCodecCtx->width,
                                pCodecCtx->height);
    buffer=(uint8_t *)av_malloc(numBytes*sizeof(uint8_t));
    
    // Assign appropriate parts of buffer to image planes in pFrameRGB
    // Note that pFrameRGB is an AVFrame, but AVFrame is a superset
    // of AVPicture
    avpicture_fill((AVPicture *)pFrameRGB, buffer, AV_PIX_FMT_RGB24,
                   pCodecCtx->width, pCodecCtx->height);
    
    // initialize SWS context for software scaling
    sws_ctx = sws_getContext(pCodecCtx->width,
                             pCodecCtx->height,
                             pCodecCtx->pix_fmt,
                             pCodecCtx->width,
                             pCodecCtx->height,
                             AV_PIX_FMT_RGB24,
                             SWS_BILINEAR,
                             NULL,
                             NULL,
                             NULL
                             );
    
    // Read frames and save first five frames to disk
    i=0;
    while(av_read_frame(pFormatCtx, &packet)>=0) {
        // Is this a packet from the video stream?
        if(packet.stream_index==videoStream) {
            // Decode video frame
            avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
            
            // Did we get a video frame?
            if(frameFinished) {
                // Convert the image from its native format to RGB
                sws_scale(sws_ctx, (uint8_t const * const *)pFrame->data,
                          pFrame->linesize, 0, pCodecCtx->height,
                          pFrameRGB->data, pFrameRGB->linesize);
                
                // Save the frame to disk
                i++;
                AVFrame *pFrame = pFrameRGB;
                int width = pCodecCtx->width;
                int height = pCodecCtx->height;
                int iFrame = i;
                
                // header
                char temp[100];
                sprintf(temp, "P6\n%d %d\n255\n", width, height);
                
                // alloc
                char* data;
                data = (char*)malloc(strlen(temp)+height*1*width*3);
                unsigned long cursor = 0;
                
                // copy header
                memcpy(&data[cursor], temp, strlen(temp));
                cursor += strlen(temp);
                
                // body
                for(int y=0; y<height; y++) {
                    memcpy(&data[cursor], pFrame->data[0]+y*pFrame->linesize[0], 1*width*3);
                    cursor += 1*width*3;
                }
                
                char szFilename[1024];
                sprintf(szFilename, "%s/frame%d.png", [docDirectory UTF8String], iFrame);
                FILE *pFile=fopen(szFilename, "wb");
                if(pFile==NULL)
                    return;
                fwrite(data, cursor, sizeof(char *), pFile);
                // Close file
                fclose(pFile);

                free(data);
            }
        }
        
        // Free the packet that was allocated by av_read_frame
        av_packet_unref(&packet);
    }
    
    // Free the RGB image
    av_free(buffer);
    av_frame_free(&pFrameRGB);
    
    // Free the YUV frame
    av_frame_free(&pFrame);
    
    // Close the codecs
    avcodec_close(pCodecCtx);
    avcodec_close(pCodecCtxOrig);
    
    // Close the video file
    avformat_close_input(&pFormatCtx);
}

- (IBAction)add:(id)sender {
    NSString *docDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSMutableArray* imageArr = [NSMutableArray array];
    int idx = 1;
    while (true) {
        NSString *fileName = [NSString stringWithFormat:@"%@/frame%d.png", docDirectory, idx++];
        UIImage *image = [UIImage imageWithContentsOfFile:fileName];
        if (image == nil) {
            break;
        }
        [imageArr addObject:image];
    }
    if ([imageArr count] <= 0) {
        return;
    }
    self.imageView = [[UIImageView alloc] initWithImage:[imageArr objectAtIndex:0]];
    self.imageView.frame = CGRectMake(0, 300, 300, 300);
    [self.imageView setAnimationImages:imageArr];
    [self.imageView setAnimationRepeatCount:INT_MAX];
    [self.imageView startAnimating];
    [self.view addSubview:self.imageView];
}

- (IBAction)del:(id)sender {
    [self.imageView stopAnimating];
    [self.imageView removeFromSuperview];
    self.imageView = nil;
}

@end
